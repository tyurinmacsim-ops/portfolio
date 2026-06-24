# Руководство: запуск и удаление `k8s-box`

Документ выстроен сверху вниз по сложности:

1. Базовый запуск/удаление через `bootstrap-k8s-box.sh` (рекомендуется).
2. Операционные команды через `platform-maintenance.sh`.
3. Ручной запуск по модулям через `terragrunt`.

Для внутреннего CI-режима команды из этого руководства оборачиваются в конвейер.
См.: [docs/internal-infra-pipeline.md](./internal-infra-pipeline.md)

Перед первым запуском рекомендуется отдельно прочитать модель источников значений:
См.: [docs/configuration-model.md](./configuration-model.md)

---

## 1. Предпосылки

Если нужен отдельный стек под конкретного заказчика по входным параметрам (нагрузка, сеть, политика), сначала сгенерируй его:

```bash
cd <path-to-coretech>/k8s-box
cp profiles/cluster-requirements.example.env profiles/<company>-<env>.env
./scripts/scaffold-stack-from-requirements.sh \
  --requirements profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env>
cd ../k8s-box-<company>-<env>
```

Подробный сценарий: [docs/requirements-driven-stack.md](./requirements-driven-stack.md)

Сначала создай локальный файл переменных из шаблона:

```bash
cd <path-to-coretech>/k8s-box
cp .env.example .env
```

Для универсального запуска (в любой компании) обязательно заполни в `.env`:

- `K8S_BOX_GITLAB_API_URL`
- `K8S_BOX_GITLAB_GROUP_PATH`
- `K8S_BOX_GITLAB_SUBGROUP`
- `K8S_BOX_STATIC_GIT_REPO_BASE_URL`
- `K8S_BOX_GITLAB_REPO_USER`
- `K8S_BOX_GITLAB_REPO_TOKEN` (или `GITLAB_TOKEN`)
- `ARGOCD_ADMIN_PASSWORD`

Если не хочется дублировать десятки несекретных параметров в `.env`, выбери готовый profile-файл из репозитория и подгрузи его поверх `.env`:

```bash
set -a
source .env
source profiles/test-minimal.env
set +a
```

Готовые варианты:

- `profiles/test-minimal.env`
- `profiles/dev-standard.env`
- `profiles/prod-baseline.env`

Для `YC` токена лучший практический вариант такой:

- не хранить короткоживущий `TF_VAR_YC_TOKEN` в `.env`;
- перед рабочей сессией получать свежий токен из активного `yc profile`;
- в `.env` держать только остальные постоянные параметры.

Для вариативности инфраструктуры (помимо observability) заполни минимум:

- `K8S_BOX_CLUSTER_PROFILE` (`test|dev|prod`)
- `K8S_BOX_DEPLOYMENT_ENV`
- `K8S_BOX_SUBNET_CIDR`
- `K8S_BOX_CLUSTER_NAME`
- `K8S_BOX_CLUSTER_VERSION`
- `K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS`
- `K8S_BOX_WORKER_MIN|K8S_BOX_WORKER_MAX|K8S_BOX_WORKER_INITIAL`
- `K8S_BOX_NODE_CORES|K8S_BOX_NODE_MEMORY_GB|K8S_BOX_NODE_BOOT_DISK_GB`
- `K8S_BOX_ENABLE_NLB_HC_RULE`
- `K8S_BOX_VAULT_PROFILE|K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS|K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST`
- `K8S_BOX_OBSERVABILITY_STACK|K8S_BOX_OBSERVABILITY_PROFILE|K8S_BOX_OBSERVABILITY_SECRET_PROVIDER|K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST`

Если нужен полностью кастомный layout node groups, используй `K8S_BOX_NODE_GROUPS_JSON`.

Для режима `apply-runner` дополнительно:

- `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN` (или `K8S_BOX_GITLAB_RUNNER_TOKEN`)
- `K8S_BOX_GITLAB_URL` (опционально, будет вычислен из `K8S_BOX_GITLAB_API_URL`)

Где взять токен runner в GitLab:

1. Открой проект (или группу), где будет работать CI.
2. Перейди `Build -> Runners`.
3. Нажми `New project runner` (или `New group runner`).
4. Выбери executor `shell`, задай тег `infra-runner`.
5. Скопируй runner token и положи в `.env` как `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN`.

Далее загрузи переменные:

```bash
cd <path-to-coretech>/k8s-box
set -a; source .env; set +a
```

Проверь `.env` перед любым `plan/apply`:

```bash
./scripts/check-env.sh
```

Если ранее `cluster apply` или ручные `yc iam service-account create` / `add-access-binding`
зависали без явной ошибки, сначала прогоняй отдельный smoke-check YC IAM:

```bash
./scripts/bootstrap-k8s-box.sh preflight-iam
```

Этот режим проверяет короткий цикл:
- создание временного service account;
- выдачу folder access binding;
- снятие binding;
- удаление временного service account.

Если `preflight-iam` завершается по timeout, не продолжай `apply-cluster`:
это внешний блокер YC IAM backend, а не обычная ошибка Terragrunt-кода.

Если запуск идет в CI или на отдельной runner VM и рядом нет checkout `infrastructure`, сначала подтяни GitOps-репозиторий и синхронизируй runtime-профиль:

```bash
./scripts/ensure-infra-repo.sh
./scripts/apply-platform-runtime-profile.sh
```

Проверка инструментов:

```bash
terraform version
terragrunt version
yc version
kubectl version --client
```

Получить свежий токен:

```bash
source <(./scripts/refresh-yc-token.sh)
```

Для прямого ручного `terragrunt plan/apply` это предпочтительный способ.
Иначе возможна ситуация, когда часть модулей планируется, а модули с `data sources`
падают на `Unauthenticated`, потому что в `.env` остался старый IAM token.

Если в `.env` лежит старый токен и нужно запустить команду прямо сейчас:

```bash
LOAD_DOTENV=false bash -lc 'source <(./scripts/refresh-yc-token.sh) && ./scripts/bootstrap-k8s-box.sh <mode>'
```

---

## 2. Важно про отдельный стек

Если нужен второй независимый стек (второй folder рядом), нужен отдельный state.

Правильно создавать отдельную копию без локального state/cache:

```bash
cd <path-to-coretech>
rsync -a k8s-box/ k8s-box-<new-stack>/ \
  --exclude .git \
  --exclude .terragrunt-cache \
  --exclude .terraform
```

Если копия уже сделана:

```bash
cd <path-to-coretech>/k8s-box-<new-stack>
find . -type d -name .terragrunt-cache -prune -exec rm -rf {} +
find . -type d -name .terraform -prune -exec rm -rf {} +
```

---

## 3. Базовый запуск через `bootstrap` (рекомендуется)

Показать доступные режимы:

```bash
./scripts/bootstrap-k8s-box.sh --help
```

Минимальный запуск только кластера:

```bash
./scripts/bootstrap-k8s-box.sh apply-cluster
```

Если YC IAM недавно вел себя нестабильно, сначала выполни:

```bash
./scripts/bootstrap-k8s-box.sh preflight-iam
```

Для test-профиля рекомендуемая схема доступа такая:

- не использовать внешний cloud LoadBalancer;
- держать `K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS=false`;
- держать `K8S_BOX_ENABLE_NLB_HC_RULE=false`;
- заходить в сервисы через `kubectl port-forward` или через VPN VM.

Это уменьшает стоимость стенда и убирает двусмысленность: test проверяет работоспособность платформы, а не внешний ingress-контур.

Отдельно поднять внешний infra-runner:

```bash
./scripts/bootstrap-k8s-box.sh apply-runner
```

Проверить, что runner зарегистрировался и находится в статусе `online`:

1. GitLab: `Build -> Runners` должен показать runner со статусом `online`.
2. На VM: `sudo gitlab-runner list` и `sudo systemctl status gitlab-runner`.

Отдельно поднять VPN VM:

```bash
./scripts/bootstrap-k8s-box.sh apply-vpn
./scripts/vpn-smoke-check.sh
```

Рекомендуемый режим для инженерного доступа:
- `K8S_BOX_VPN_VM_SSH_MODE=native`
- `K8S_BOX_VPN_VM_ENABLE_OSLOGIN=false`
- `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub`
- `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH=~/.ssh/id_ed25519`

Если в облаке или организации принудительно включен `OS Login`, переключи operational-доступ:

```bash
export K8S_BOX_VPN_VM_SSH_MODE=yc
```

Тогда локальные VPN-скрипты будут использовать `yc compute ssh`. Это требует, чтобы у инженера уже были настроены `OS Login profile` и SSH key в организации.

Выдать клиентский конфиг WireGuard инженеру:

```bash
./scripts/vpn-create-wireguard-client.sh laptop
```

Подключение инженера:
- `macOS`: импортировать `*.conf` в приложение `WireGuard`
- `Windows`: импортировать `*.conf` в `WireGuard for Windows`

Текущий поддерживаемый operational-сценарий для VPN:
- `WireGuard` — основной;
- `OpenVPN` — legacy-режим, не является рекомендуемым путем эксплуатации.

Полный запуск (кластер + `vault-infra` + `argocd`):

```bash
./scripts/bootstrap-k8s-box.sh apply
```

Опциональный plan:

```bash
./scripts/bootstrap-k8s-box.sh plan-cluster
./scripts/bootstrap-k8s-box.sh plan
./scripts/bootstrap-k8s-box.sh plan-runner
./scripts/bootstrap-k8s-box.sh plan-vpn
```

В CI для `plan:*` публикуются артефакты:

- `plan-*.log` — сырой лог job,
- `plan-*.clean.log` — лог без ANSI-цветов,
- `plan-*.summary` — краткий итог (`Plan: ...`, `No changes`, ошибки/скипы).

Проверка после успешного полного `apply`:

```bash
kubectl get nodes -o wide
kubectl get ns
kubectl -n argocd get applications
```

---

## 4. Удаление через bootstrap

Удалить стек без удаления folder (безопасный режим по умолчанию):

```bash
SKIP_FOLDER_DESTROY=true ./scripts/bootstrap-k8s-box.sh destroy
```

Удалить стек вместе с folder:

```bash
SKIP_FOLDER_DESTROY=false ./scripts/bootstrap-k8s-box.sh destroy
```

Только кластерный слой (без `vault-infra`/`argocd`):

```bash
./scripts/bootstrap-k8s-box.sh destroy-cluster
```

Удалить только внешний infra-runner:

```bash
./scripts/bootstrap-k8s-box.sh destroy-runner
```

Удалить только VPN VM:

```bash
./scripts/bootstrap-k8s-box.sh destroy-vpn
```

Полный цикл удалить+поднять:

```bash
./scripts/bootstrap-k8s-box.sh recreate
```

Примечание по Vault KMS: при `destroy` скрипт сам переводит `kms_key_deletion_protection=false`, чтобы ключ удалялся без ручного `-var`.

---

## 5. Операционные команды (после развертывания)

Эти команды запускать только когда кластер и ArgoCD уже подняты:

```bash
./scripts/set-vault-profile.sh test --enable-backup-manifests true --enable-backup-in-test false
./scripts/set-observability-stack.sh vm-loki-grafana --profile test
./scripts/set-observability-stack.sh prom-loki-grafana --profile test
./scripts/set-observability-stack.sh vm-loki-grafana --profile prod --secret-provider vso
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

`set-observability-stack.sh` переключает активный стек мониторинга в `infrastructure/observability/values.yaml`:

- `vm-loki-grafana` — VictoriaMetrics + Loki + Grafana.
- `prom-loki-grafana` — kube-prometheus-stack + Loki + Grafana.
- `--secret-provider vso` — рекомендуемый вариант для связки с Vault.
- `--secret-provider external-secrets` — вариант для внешнего secret backend.
- `--secret-provider manual` — вариант без операторов секретов.

`set-vault-profile.sh` переключает runtime-профиль Vault в `infrastructure/vault/values.yaml`:

- `test` — облегченный standalone режим.
- `prod` — базовый HA-профиль.
- `--enable-backup-manifests true|false` — подключать ли backup source в Argo Application.
- `--enable-backup-in-test true|false` — разрешать ли backup source в test-профиле.

Для переключения кластера по профилю/размеру без правки `terragrunt.hcl` меняй `.env`:

- профиль: `K8S_BOX_CLUSTER_PROFILE=test|dev|prod`
- ресурсы нод: `K8S_BOX_NODE_*`
- autoscaling: `K8S_BOX_WORKER_*`, `K8S_BOX_MONITORING_*`
- сеть/доступ: `K8S_BOX_SUBNET_CIDR`, `K8S_BOX_API_ALLOWED_CIDRS`, `K8S_BOX_SSH_ALLOWED_CIDRS`

Если kube-context не настроен, `platform-maintenance.sh` завершится с понятной ошибкой.

---

## 6. Ручной запуск через Terragrunt (продвинутый режим)

Пояснение по `plan` на "чистом" стеке:

- в зависимостях Terragrunt добавлены `mock_outputs` для команд `validate/init/plan/destroy/output`;
- это позволяет делать `terragrunt plan` по отдельным модулям до первого `apply`;
- в таком плане значения зависимых ID (`folder_id`, `subnet_id`, и т.д.) будут mock-значениями, это нормально;
- реальные значения появятся после фактического `apply` зависимых модулей.
- warning вида `... has no outputs, but mock outputs provided` на пустом стеке ожидаем: это особенность Terragrunt dependency + mock outputs, а не ошибка конфигурации.

Порядок `apply`:

```bash
cd <path-to-coretech>/k8s-box
set -a; source .env; set +a

cd folder && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd vpc && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd security-group && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd vpn-vm && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd infra-runner && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd test-cluster-k8s && terragrunt init && terragrunt plan && terragrunt apply

CLUSTER_ID="$(terragrunt output -raw cluster_id)"
yc managed-kubernetes cluster get-credentials --id "$CLUSTER_ID" --external --force
cd ..

cd vault-infra && terragrunt init && terragrunt plan && terragrunt apply && cd ..
cd argocd && terragrunt init && terragrunt plan && terragrunt apply && cd ..
```

Если у тебя на руках только `folder_id` вида `b1g...`, а не `cluster_id` вида `cat...`, сначала найди кластер в этом folder:

```bash
yc managed-kubernetes cluster list --folder-id "$YC_FOLDER_ID"
yc managed-kubernetes cluster get-credentials --id "<cluster_id>" --external --force
```

Это частая путаница при ручной диагностике: `folder_id` подходит для `cluster list`, но не для `cluster get-credentials`.

Обратный порядок `destroy`:

```bash
cd <path-to-coretech>/k8s-box
set -a; source .env; set +a

cd argocd && terragrunt destroy && cd ..
cd vpn-vm && terragrunt destroy && cd ..
cd infra-runner && terragrunt destroy && cd ..
cd test-cluster-k8s && terragrunt destroy && cd ..
cd security-group && terragrunt destroy && cd ..
cd vpc && terragrunt destroy && cd ..
cd vault-infra && terragrunt destroy -var='kms_key_deletion_protection=false' && cd ..
# cd folder && terragrunt destroy && cd ..   # только если нужен полный ноль
```

---

## 7. Быстрая проверка после destroy

```bash
yc managed-kubernetes cluster list --folder-id "$YC_FOLDER_ID"
yc vpc network list --folder-id "$YC_FOLDER_ID"
yc kms symmetric-key list --folder-id "$YC_FOLDER_ID"
yc iam service-account list --folder-id "$YC_FOLDER_ID"
```

---

## 8. Восстановление при устаревшем `folder state`

Если в `folder` модуле на `plan` видишь предупреждение вида `folder not found`, значит в state остался id удаленного folder.

Выполни repair:

```bash
./scripts/repair-folder-state.sh
```

И затем повтори:

```bash
source <(./scripts/refresh-yc-token.sh)
cd folder && terragrunt plan
```

Или одной командой:

```bash
./scripts/repair-folder-state.sh --plan
```

---

## 9. Доступы в UI после развертывания

ArgoCD:

```bash
kubectl -n argocd get secret argocd-admin-credentials -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n argocd get secret argocd-admin-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```

Grafana:

```bash
kubectl -n monitoring get secret vm-stack-grafana -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl -n monitoring get secret vm-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Vault (`test`):

```bash
jq -r '.root_token' ~/.k8s-box/vault/test-init.json
```
