# Модель конфигурации и источники значений

Этот документ фиксирует единый подход к тому, откуда берутся значения для `k8s-box` и `infrastructure`, в каком порядке они применяются и почему часть секретов нельзя ожидать из Vault с самого начала.

## 1. Слои конфигурации

В решении используются пять слоев значений:

1. `defaults` в коде
2. профиль окружения
3. явные overrides через `env` или `CI variables`
4. bootstrap-секреты
5. runtime-секреты из Vault

Эти слои нельзя смешивать. Если смешать bootstrap и runtime-секреты, получится замкнутый круг: Vault еще не развернут, а значения уже требуются для его же развертывания.

## 2. Приоритет источников значений

Приоритет должен быть таким:

1. `defaults` в коде
2. профиль (`test|dev|prod` или customer-specific profile)
3. `env` / `CI variables`
4. runtime-секреты из Vault для уже запущенных сервисов

Практически это означает:

- код задает безопасную базу;
- профиль задает типовой сценарий;
- `env` и `CI variables` вносят точные отклонения под конкретный стенд;
- Vault подключается только после bootstrap.

## 3. Что относится к каждому слою

### 3.1 Defaults в коде

Это несекретные значения по умолчанию:

- версия Kubernetes;
- release channel;
- CNI;
- минимальные размеры test-кластера;
- базовый стек observability;
- базовые `values.yaml` для Vault/Observability;
- дефолтные profile presets.

Где это хранится:

- [cluster-profiles.hcl](../profiles/cluster-profiles.hcl)
- [env.hcl](../env.hcl)
- `infrastructure/vault/values.yaml` в соседнем runtime-репозитории
- `infrastructure/observability/values.yaml` в соседнем runtime-репозитории

### 3.2 Профиль окружения

Профиль задает готовый набор параметров:

- `test`
- `dev`
- `prod`
- в дальнейшем: customer-specific profiles

Профиль должен отвечать за:

- размер кластера;
- public/private master;
- наличие выделенной monitoring node group;
- включение/отключение публичных LB;
- режим Vault;
- режим Observability;
- backup policy.

### 3.3 Overrides через env / CI

Это точечные отклонения от профиля.

Примеры:

- `K8S_BOX_CLUSTER_VERSION`
- `K8S_BOX_CLUSTER_NAME`
- `K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS`
- `K8S_BOX_ENABLE_NLB_HC_RULE`
- `K8S_BOX_OBSERVABILITY_STACK`
- `K8S_BOX_OBSERVABILITY_PROFILE`
- `K8S_BOX_OBSERVABILITY_SECRET_PROVIDER`
- `K8S_BOX_VAULT_PROFILE`

Идея простая:

- локально инженер использует `.env`;
- в GitLab pipeline используются `CI variables`;
- при подготовке отдельного заказчика можно использовать profile-файл из `profiles/`.

### 3.4 Bootstrap-секреты

Это секреты, без которых стартовая инфраструктура вообще не поднимется.

Типовые bootstrap-секреты:

- `TF_VAR_YC_TOKEN` / `YC_TOKEN`
- `GITLAB_TOKEN`
- `K8S_BOX_GITLAB_REPO_TOKEN`
- `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN`
- начальный `ARGOCD_ADMIN_PASSWORD`

Их нельзя ожидать из Vault, потому что:

- Vault еще не развернут;
- runner еще не зарегистрирован;
- ArgoCD еще не развернут;
- GitOps repo еще не подключен.

### 3.5 Runtime-секреты из Vault

Это секреты для уже работающих сервисов.

Примеры:

- Telegram token для Alertmanager;
- app API tokens;
- пароли интеграций;
- ротационные секреты приложений;
- внутренние runtime credentials.

Они должны приходить через:

- `VSO` как предпочтительный путь;
- `ESO` как альтернативу;
- `manual` как fallback.

## 4. Что где задавать

### 4.1 Локальный запуск из репозитория

Используются три типа файлов:

1. `.env.example`
2. `.env`
3. `profiles/*.env`

Роли файлов:

- `.env.example` — шаблон структуры, без рабочих секретов;
- `.env` — локальные bootstrap-секреты и overrides, файл игнорируется git;
- `profiles/*.env` — несекретные наборы параметров под окружение или заказчика.

Пример:

```bash
cp .env.example .env
cp profiles/cluster-requirements.example.env profiles/customer-a-test.env
set -a
source .env
source profiles/customer-a-test.env
set +a
./scripts/bootstrap-k8s-box.sh apply
```

### 4.2 Запуск через GitLab CI/CD

В GitLab не нужно хранить десятки несекретных переменных по одной.

Рекомендуемая схема:

- в `CI variables` держать только секреты;
- профиль и несекретные параметры хранить в коде;
- в pipeline передавать 2-5 управляющих переменных.

Что разумно держать в `CI variables`:

- `TF_VAR_YC_TOKEN`
- `GITLAB_TOKEN`
- `K8S_BOX_GITLAB_REPO_TOKEN`
- `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN`

Для локального запуска не обновляй `TF_VAR_YC_TOKEN`, `TF_VAR_yc_token` и `YC_TOKEN`
в одной смешанной строке `export`: это типовая shell-ловушка, из-за которой в нижний регистр
может попасть старое значение. Рекомендуемый способ:

```bash
source <(./scripts/refresh-yc-token.sh)
```

Что разумно выбирать как управляющие переменные:

- `K8S_BOX_CLUSTER_PROFILE`
- `K8S_BOX_DEPLOYMENT_ENV`
- `K8S_BOX_OBSERVABILITY_STACK`
- `K8S_BOX_OBSERVABILITY_PROFILE`
- `K8S_BOX_VAULT_PROFILE`

Лучший практический вариант:

- хранить profile-файлы в репозитории;
- в CI передавать только путь к профилю или имя профиля;
- pipeline подхватывает этот профиль и применяет его.

Пример:

- `K8S_BOX_PROFILE_FILE=profiles/test-minimal.env`

Готовые profile-файлы в репозитории:

- [test-minimal.env](../profiles/test-minimal.env)
- [dev-standard.env](../profiles/dev-standard.env)
- [prod-baseline.env](../profiles/prod-baseline.env)

Для локальной проверки profile-файла используй:

```bash
./scripts/validate-profile-file.sh profiles/test-minimal.env
```

## 5. Порядок использования значений

### Этап 1. Bootstrap

Используются:

- `TF_VAR_YC_TOKEN`
- GitLab tokens
- runner registration token
- базовые cluster/profile overrides

На этом этапе поднимаются:

1. `folder`
2. `vpc`
3. `security-group`
4. `vpn-vm` (если нужен)
5. `infra-runner` (если нужен)
6. `test-cluster-k8s`
7. `vault-infra`
8. `argocd`

Для `vpn-vm` базовый поддерживаемый сценарий такой:

- `WireGuard` — основной режим;
- `OpenVPN` — legacy-режим и не является обязательной частью стартовой эксплуатации.
- для operational-доступа инженера рекомендуем:
  - `K8S_BOX_VPN_VM_SSH_MODE=native`
  - `K8S_BOX_VPN_VM_ENABLE_OSLOGIN=false`
  - SSH key path через `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH` / `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH`
- если в организации принудительно используется `OS Login`, operational-путь переключается на:
  - `K8S_BOX_VPN_VM_SSH_MODE=yc`
  - при этом `vpn-smoke-check.sh` и `vpn-create-wireguard-client.sh` ходят через `yc compute ssh`, а не через локальный `ssh`.

Операционная модель:
- сервер VPN поднимается кодом;
- клиентский конфиг выдается отдельным скриптом;
- инженеру передается только `WireGuard`-конфиг, а не общий набор VPN-вариантов.

### Этап 2. Platform runtime

После того как кластер и ArgoCD уже подняты, применяются runtime-варианты:

- `Vault profile`
- `Observability stack`
- `Observability profile`
- `secret provider`

Точка входа:

- [apply-platform-runtime-profile.sh](../scripts/apply-platform-runtime-profile.sh)

### Этап 3. Runtime secrets

Когда Vault уже развернут, секреты приложений должны приходить:

- из Vault через `VSO`;
- либо через `ESO`;
- либо как временный manual fallback.

## 6. Почему не все значения нужно тащить в GitLab CI variables

Если пытаться хранить всю конфигурацию по одной переменной в GitLab:

- становится тяжело сопровождать pipeline;
- трудно понять, что реально является источником истины;
- сложно переносить конфигурацию между проектами;
- легко получить рассинхрон между кодом и UI GitLab.

Поэтому правильнее:

- секреты держать в GitLab variables;
- profile/defaults хранить в коде;
- Vault использовать только для runtime-секретов.

## 7. Рекомендуемая практическая схема

### Для инженера локально

1. заполнить `.env`;
2. выбрать или создать profile-файл;
3. выполнить `bootstrap`;
4. применить runtime profile;
5. проверить Vault/Observability.

### Для CI

1. хранить только секреты в GitLab variables;
2. выбрать profile через одну переменную pipeline `K8S_BOX_PROFILE_FILE`;
3. выполнить `plan/apply`;
4. применить runtime profile;
5. дать сервисам получить runtime secrets из Vault.

## 8. Что еще надо улучшить

Этот документ фиксирует текущую модель. Следующие шаги остаются такими:

- расширить runtime-secret pattern с Alertmanager на остальные секреты платформы;
- добавить инженерные customer-specific profile-файлы поверх базовых `test/dev/prod`;
- при необходимости вынести часть проверки profile/requirements в более строгую схему валидации.

## 9. Связанные документы

- [README.md](../README.md)
- [deployment-launch-runbook.md](./deployment-launch-runbook.md)
- [requirements-driven-stack.md](./requirements-driven-stack.md)
- [customer-requirements-questionnaire.md](./customer-requirements-questionnaire.md)
- [internal-infra-pipeline.md](./internal-infra-pipeline.md)
- [vault-observability-runbook.md](./vault-observability-runbook.md)
