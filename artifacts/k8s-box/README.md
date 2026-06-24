# K8s-box в Yandex Cloud (Terraform + Terragrunt)

Публичная sanitized-копия рабочего toolkit для портфолио.

Что исключено из этой копии:

- `.git` и локальная история;
- `.env` с рабочими значениями;
- `.generated` и runtime-артефакты;
- клиентские VPN-конфиги из `.artifacts/vpn-clients`;
- дублирующий рабочий каталог `k8s-box-main`.

Что не входит в эту публичную копию:

- соседний GitOps/runtime-репозиторий `infrastructure`, на который ссылается часть automation и документации.

Репозиторий поднимает test-платформу в Yandex Cloud:

1. `folder`
2. `vpc`
3. `security-group`
4. `vpn-vm` (опциональная VPN-точка входа)
5. `infra-runner` (внешний GitLab runner, опционально)
6. `test-cluster-k8s`
7. `vault-infra`
8. `argocd`

Далее ArgoCD разворачивает runtime-приложения из соседнего репозитория `infrastructure` (Vault, Observability).

## Что уже вариативно

Решение уже можно использовать как внутренний инженерный toolkit под разные вводные заказчика, но с честными границами текущей реализации.

Через код уже переключается:

- инфраструктурный профиль кластера:
  - версия Kubernetes,
  - release channel,
  - CNI (`calico|cilium`),
  - публичность master endpoint,
  - разрешение/запрет публичных LoadBalancer-сервисов,
  - autoscaling и sizing node groups,
  - выделенная monitoring-группа,
  - security rules и CIDR-доступы, включая `nlb_hc`;
- Vault infra:
  - KMS key,
  - rotation period,
  - backup bucket,
  - service accounts;
- Vault runtime:
  - `test|prod` профиль,
  - подключение backup-manifests,
  - включение/выключение backup-manifests в test;
- Observability runtime:
  - `vm-loki-grafana` или `prom-loki-grafana`,
  - `test|dev|prod` профиль,
  - провайдер Telegram-секрета для Alertmanager:
    - `vso`,
    - `external-secrets`,
    - `manual`.

Границы текущей реализации:

- решение целенаправленно поддерживает только `Yandex Cloud`;
- вариативность предусмотрена для разных клиентских сценариев и профилей внутри `YC`;

Дополнительно:

- runtime-вариант Vault и Observability можно задавать через env/CI variables без ручной правки соседнего `infrastructure`;
- единая точка входа для этого режима: `./scripts/apply-platform-runtime-profile.sh`;
- если рядом нет checkout `infrastructure`, automation может подтянуть его через `./scripts/ensure-infra-repo.sh`.

Готовые profile-файлы для запуска и CI:

- [profiles/test-minimal.env](./profiles/test-minimal.env)
- [profiles/dev-standard.env](./profiles/dev-standard.env)
- [profiles/prod-baseline.env](./profiles/prod-baseline.env)

Рекомендуемая схема:

- секреты держать в `.env` или GitLab CI variables;
- несекретные параметры выбирать одним profile-файлом;
- поверх profile при необходимости переопределять отдельные значения.

---

## Маршрут чтения (сверху вниз по сложности)

1. Новичок, первый запуск: [docs/quickstart-test-cluster.md](./docs/quickstart-test-cluster.md)
2. Модель конфигурации и источники значений: [docs/configuration-model.md](./docs/configuration-model.md)
3. Внутренний инфра-пайплайн (runner + CI-поток): [docs/internal-infra-pipeline.md](./docs/internal-infra-pipeline.md)
4. Запуск от требований (requirements -> готовый стек): [docs/requirements-driven-stack.md](./docs/requirements-driven-stack.md)
5. Опросник для инженера по требованиям заказчика: [docs/customer-requirements-questionnaire.md](./docs/customer-requirements-questionnaire.md)
6. Полное руководство запуска/удаления: [docs/deployment-launch-runbook.md](./docs/deployment-launch-runbook.md)
7. Эксплуатация и обновления: [docs/platform-update-maintenance.md](./docs/platform-update-maintenance.md)
8. Vault + Observability: [docs/vault-observability-runbook.md](./docs/vault-observability-runbook.md)
9. Типовые ошибки и принятые решения: [docs/known-errors-decisions.md](./docs/known-errors-decisions.md)
10. VPN VM и WireGuard: [docs/vpn-runbook.md](./docs/vpn-runbook.md)

---

## Быстрый старт (минимум шагов)

### 1. Подготовь инструменты

- `terraform`
- `terragrunt`
- `yc`
- `kubectl`

### 2. Заполни `env.hcl`

Обязательные поля:

- `cloud_id`
- `yc_zone`
- `network_name`
- `folder_name`

Важно:

- если просто поменять `folder_name` в том же state, Terraform переименует управляемый folder;
- для отдельного второго folder нужен отдельный state (отдельная копия `k8s-box` без `.terragrunt-cache/.terraform`).

### 2.1 Подготовь локальный `.env` по шаблону

```bash
cp .env.example .env
```

Для рабочего запуска заполни в `.env` обязательно:

- `TF_VAR_YC_TOKEN` (или `YC_TOKEN`)
- `K8S_BOX_GITLAB_API_URL`
- `K8S_BOX_GITLAB_GROUP_PATH`
- `K8S_BOX_GITLAB_SUBGROUP`
- `K8S_BOX_STATIC_GIT_REPO_BASE_URL`
- `K8S_BOX_GITLAB_REPO_USER`
- `K8S_BOX_GITLAB_REPO_TOKEN` (или `GITLAB_TOKEN`)
- `ARGOCD_ADMIN_PASSWORD`
- `K8S_BOX_VAULT_PROFILE`
- `K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS`
- `K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST`
- `K8S_BOX_OBSERVABILITY_STACK`
- `K8S_BOX_OBSERVABILITY_PROFILE`
- `K8S_BOX_OBSERVABILITY_SECRET_PROVIDER`
- `K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST`

Для test-стенда дополнительно рекомендуется явно держать:

- `K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS=false`
- `K8S_BOX_ENABLE_NLB_HC_RULE=false`

` .env` уже игнорируется git и не должен попадать в репозиторий.

Проверка заполнения `.env`:

```bash
./scripts/check-env.sh
```

Скрипт валидирует обязательные переменные и `CHANGE_ME` плейсхолдеры.

### 2.2 (Опционально) Подготовь стек на основе собранных требований

Если по проекту еще нет готового профиля, инженер сначала собирает вводные по нагрузке, сети, доступам, отказоустойчивости и ограничениям среды.
На основе этих требований можно использовать генератор как вспомогательный инструмент для подготовки стартового стека:

```bash
cp profiles/cluster-requirements.example.env profiles/<company>-<env>.env
./scripts/scaffold-stack-from-requirements.sh \
  --requirements profiles/<company>-<env>.env \
  --validate-only
./scripts/scaffold-stack-from-requirements.sh \
  --requirements profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env>
```

Подробно: [docs/requirements-driven-stack.md](./docs/requirements-driven-stack.md)
Опросник для сбора вводных: [docs/customer-requirements-questionnaire.md](./docs/customer-requirements-questionnaire.md)

Генератор не заменяет инженерное решение, а ускоряет подготовку базовой конфигурации под типовой сценарий.

Если используется готовый profile-файл, его можно проверить отдельно:

```bash
./scripts/validate-profile-file.sh profiles/test-minimal.env
```

### 3. Задай токен

```bash
export TF_VAR_YC_TOKEN="$(yc iam create-token)"
export TF_VAR_yc_token="$TF_VAR_YC_TOKEN"
```

### 4. Запусти bootstrap

Только runner (для начальной настройки CI):

```bash
./scripts/bootstrap-k8s-box.sh apply-runner
```

Для `apply-runner` обязательно задать:

- `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN` (или `K8S_BOX_GITLAB_RUNNER_TOKEN`)
- `K8S_BOX_GITLAB_URL` (или `K8S_BOX_GITLAB_API_URL`, из которого URL будет вычислен)

Только VPN VM:

```bash
./scripts/bootstrap-k8s-box.sh apply-vpn
./scripts/vpn-smoke-check.sh
```

Для VPN test/dev сценария рекомендуемый operational-режим:
- `K8S_BOX_VPN_VM_SSH_MODE=native`
- `K8S_BOX_VPN_VM_ENABLE_OSLOGIN=false`
- `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub`
- `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH=~/.ssh/id_ed25519`

Если в организации принудительно включен `OS Login`, operational-доступ нужно переключать на:
- `K8S_BOX_VPN_VM_SSH_MODE=yc`

В этом режиме `vpn-smoke-check.sh` и `vpn-create-wireguard-client.sh` используют `yc compute ssh`, а не обычный локальный `ssh`.

Рекомендуемый VPN-стек для инженеров:
- `WireGuard` как основной путь;
- `OpenVPN` только как legacy-флаг в модуле, без полноценной operational-поддержки.

Только кластер:

```bash
./scripts/bootstrap-k8s-box.sh apply-cluster
```

Полный стек (кластер + `vault-infra` + `argocd`):

```bash
./scripts/bootstrap-k8s-box.sh apply
```

### 5. Проверь результат

После `apply-cluster`:

```bash
kubectl get nodes
```

Для test-профиля доступ к сервисам предполагается без внешнего LoadBalancer:

- через `kubectl port-forward`,
- через VPN VM (`WireGuard`),
- через внутренние `ClusterIP`/Ingress-маршруты внутри контура.

Это сделано намеренно: test должен проверять общую концепцию кластера и платформы без лишних облачных расходов.

После полного `apply` (с ArgoCD):

```bash
kubectl get nodes
kubectl -n argocd get applications
```

Если контекст не появился автоматически:

```bash
cd test-cluster-k8s
CLUSTER_ID="$(terragrunt output -raw cluster_id)"
cd ..
yc managed-kubernetes cluster get-credentials --id "$CLUSTER_ID" --external --force
```

---

## Команды (по назначению)

### Установка/удаление стека

```bash
./scripts/bootstrap-k8s-box.sh --help
./scripts/bootstrap-k8s-box.sh plan
./scripts/bootstrap-k8s-box.sh apply
./scripts/bootstrap-k8s-box.sh plan-vpn
./scripts/bootstrap-k8s-box.sh apply-vpn
./scripts/bootstrap-k8s-box.sh destroy-vpn
./scripts/bootstrap-k8s-box.sh plan-runner
./scripts/bootstrap-k8s-box.sh apply-runner
./scripts/bootstrap-k8s-box.sh destroy-runner
./scripts/bootstrap-k8s-box.sh apply-cluster
./scripts/bootstrap-k8s-box.sh destroy
./scripts/bootstrap-k8s-box.sh destroy-cluster
./scripts/bootstrap-k8s-box.sh recreate
./scripts/bootstrap-k8s-box.sh recreate-cluster
```

Примечания:

- по умолчанию `destroy` не удаляет folder (`SKIP_FOLDER_DESTROY=true`);
- для удаления folder: `SKIP_FOLDER_DESTROY=false ./scripts/bootstrap-k8s-box.sh destroy`;
- при `destroy` для `vault-infra` скрипт сам выставляет `kms_key_deletion_protection=false`.

### Эксплуатация и обновления (после развертывания)

```bash
./scripts/set-vault-profile.sh test --enable-backup-manifests true --enable-backup-in-test false
./scripts/set-vault-profile.sh prod --enable-backup-manifests true
./scripts/set-observability-stack.sh vm-loki-grafana --profile test
./scripts/set-observability-stack.sh prom-loki-grafana --profile test
./scripts/set-observability-stack.sh vm-loki-grafana --profile prod --secret-provider vso
./scripts/set-observability-stack.sh prom-loki-grafana --profile prod --secret-provider external-secrets
./scripts/apply-platform-runtime-profile.sh
./scripts/platform-maintenance.sh plan-k8s
./scripts/platform-maintenance.sh apply-k8s
./scripts/platform-maintenance.sh plan-vault-infra
./scripts/platform-maintenance.sh apply-vault-infra
./scripts/platform-maintenance.sh plan-argocd
./scripts/platform-maintenance.sh apply-argocd
./scripts/platform-maintenance.sh sync-gitops
./scripts/platform-maintenance.sh upgrade-vault-observability
./scripts/platform-maintenance.sh status
./scripts/platform-maintenance.sh smoke-services
```

Переключение observability-стека:

- `vm-loki-grafana` — VictoriaMetrics + Loki + Grafana.
- `prom-loki-grafana` — kube-prometheus-stack + Loki + Grafana.
- `--secret-provider vso` — рекомендованный вариант по умолчанию для централизованной работы с Vault.
- `--secret-provider external-secrets` — вариант для внешнего secret backend.
- `--secret-provider manual` — fallback, если операторы секретов не нужны или еще не готовы.

Переключение Vault runtime:

- `./scripts/set-vault-profile.sh test` — облегченный standalone профиль.
- `./scripts/set-vault-profile.sh prod --enable-backup-manifests true` — базовый HA/profile для продового сценария.

Единая синхронизация runtime-варианта платформы:

- `./scripts/apply-platform-runtime-profile.sh` — берет значения из `K8S_BOX_VAULT_*` и `K8S_BOX_OBSERVABILITY_*`, применяет их в `infrastructure` и сразу валидирует GitOps-рендер.

### Ручной режим по модулям

Если нужен ручной режим, запускай `terragrunt` в порядке зависимостей:

`folder -> vpc -> security-group -> vpn-vm -> infra-runner -> test-cluster-k8s -> vault-infra -> argocd`

Подробно: [docs/deployment-launch-runbook.md](./docs/deployment-launch-runbook.md)

### CI-режим (внутренний infra-pipeline)

Текущий пайплайн встроен в репозиторий `k8s-box`:

1. На `push`/`MR` запускается `plan` по измененным директориям.
2. После merge в `main` запускается `apply`.
3. После `apply` запускаются `verify` проверки.
4. `destroy` оставлен manual.

Для platform-стадий pipeline теперь сам:

- подтягивает соседний GitOps-репозиторий `infrastructure`;
- синхронизирует runtime-профиль Vault/Observability из CI variables;
- только после этого запускает `plan/apply/verify`.

Требуется внешний GitLab runner с тегом `infra-runner`.
Подробно: [docs/internal-infra-pipeline.md](./docs/internal-infra-pipeline.md)

---

## Важно про test/prod

- В этом репозитории есть модуль кластера только для test: `test-cluster-k8s`.
- Отдельного terragrunt-модуля `prod-cluster-k8s` сейчас нет.
- `test/prod` в репозитории `infrastructure` — это профили приложений, а не создание разных кластеров.

---

## Структура репозитория

- `env.hcl` — общие параметры (`cloud_id`, `folder_name`, зона, сеть).
- `folder/`, `vpc/`, `security-group/`, `vpn-vm/`, `infra-runner/`, `test-cluster-k8s/`, `vault-infra/`, `argocd/` — terragrunt-слои.
- `yc-*-module/`, `argocd-module/` — terraform-модули, включая `yc-runner-module` и `yc-vpn-vm-module`.
- `scripts/bootstrap-k8s-box.sh` — основной lifecycle-скрипт установки/удаления.
- `scripts/platform-maintenance.sh` — скрипт обновлений и операций после развертывания.
- `scripts/repair-folder-state.sh` — исправление устаревшего `folder state` (если `folder plan` ругается `folder not found`).
- `scripts/yc-iam-smoke-check.sh` — короткая проверка create/bind/unbind/delete для YC IAM перед `apply-cluster`.
- `scripts/scaffold-stack-from-requirements.sh` — генерация отдельного стека/state по входным требованиям.
- `profiles/cluster-requirements.example.env` — шаблон входных параметров заказчика.
- `docs/` — руководства и операционные материалы.

README каждого модуля лежит внутри его директории.

---

## Частые проблемы

| Проблема | Что делать |
|----------|------------|
| `token has expired` / `UNAUTHENTICATED` | Обновить токен: `export TF_VAR_YC_TOKEN="$(yc iam create-token)"` и повторить запуск. |
| `AlreadyExists` при создании folder | Имя уже занято. Используй новое имя или отдельный state для второго стека. |
| `folder not found` в `folder plan` | Выполни `./scripts/repair-folder-state.sh`, затем повтори `terragrunt plan`. |
| `service account` / `folder IAM member` висят в `Still creating...` | Сначала выполни `./scripts/bootstrap-k8s-box.sh preflight-iam`. Если он зависает по timeout, это внешний блокер YC IAM backend, а не обычная ошибка HCL. |
| `WARN ... has no outputs, but mock outputs provided` на `plan` | На пустом стеке это ожидаемое предупреждение Terragrunt при использовании `mock_outputs`. Сам план при этом валиден и показывает будущие ресурсы. |
| `argocd` падает с `b64enc: invalid value; expected string` | Не задан токен репозитория. Проверь `K8S_BOX_GITLAB_REPO_TOKEN` или `GITLAB_TOKEN`. |
| `argocd` падает без kube-context | Получи контекст через `yc ... get-credentials` или запускай через bootstrap/maintenance с авто-подхватом context. |
| `healthcheck/redeploy` ожидает старые monitoring-app имена | Обновить `k8s-box` до актуальной версии: старые флаги ESO заменены на `alertmanagerTelegram.secretProvider` и новый набор приложений VSO/ESO/manual. |
| После `destroy` остался KMS | Повтори `./scripts/bootstrap-k8s-box.sh destroy` (в скрипте уже встроено отключение deletion protection). |

---

## Соседний репозиторий `infrastructure`

`argocd` модуль настраивает доступ ArgoCD к GitOps-репозиторию:

- базовый путь задается через `K8S_BOX_STATIC_GIT_REPO_BASE_URL` (пример: `https://gitlab.example.com/my-group/infrastructure`)
- профили приложений (`test`/`prod`) находятся уже там.

В публичную копию портфолио этот соседний runtime-репозиторий не входит.
