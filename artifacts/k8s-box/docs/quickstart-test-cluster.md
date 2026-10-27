# Быстрый старт: test-кластер с нуля (для новичка)

Цель: поднять с нуля **folder + test Kubernetes кластер** в Yandex Cloud с минимальным количеством шагов.

## 1. Открой репозиторий

```bash
cd <path-to-coretech>/k8s-box
```

Создай локальный `.env` из шаблона:

```bash
cp .env.example .env
```

Если запускаешь не базовый test-стек, а отдельный клиентский стек по требованиям, сначала используй:

```bash
cp profiles/cluster-requirements.example.env profiles/<company>-<env>.env
./scripts/scaffold-stack-from-requirements.sh \
  --requirements profiles/<company>-<env>.env \
  --validate-only
./scripts/scaffold-stack-from-requirements.sh \
  --requirements profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env>
cd ../k8s-box-<company>-<env>
cp .env.example .env
```

## 2. Заполни `env.hcl`

Файл: `env.hcl`

Проверь 4 поля:

- `cloud_id` — ID твоего облака в Yandex Cloud.
- `yc_zone` — зона, обычно `ru-central1-a`.
- `network_name` — оставь `k8s-vpc-01`, если нет своей схемы.
- `folder_name` — имя каталога для этого стека (например `my-k8s-folder`).

Пример:

```hcl
locals {
  cloud_id     = "b1gxxxxxxxxxxxxxxxxx"
  yc_zone      = "ru-central1-a"
  network_name = "k8s-vpc-01"
  folder_name  = "my-k8s-folder"
}
```

Важно:

- если ты просто поменяешь `folder_name` в той же директории/state, Terraform переименует уже существующий folder;
- это не создаёт второй folder автоматически.
- если folder с таким именем уже есть в этом cloud, `bootstrap-k8s-box.sh apply*` автоматически импортирует его в state (чтобы не падать с `AlreadyExists`).

Если нужен отдельный новый folder (например `my-k8s-folder-prod`) без изменения текущего:

1. Сделай отдельную копию директории `k8s-box` (или отдельный backend key/state).
2. В этой копии задай свой `folder_name`.
3. Запускай `terragrunt apply` из этой копии.

Рекомендуемый безопасный способ копии (без переноса локального state/cache):

```bash
cd <path-to-coretech>
rsync -a k8s-box/ k8s-box-<new-stack>/ \
  --exclude .git \
  --exclude .terragrunt-cache \
  --exclude .terraform
```

Если копия уже сделана, перед запуском очисти кэш в ней:

```bash
cd <path-to-coretech>/k8s-box-<new-stack>
find . -type d -name .terragrunt-cache -prune -exec rm -rf {} +
find . -type d -name .terraform -prune -exec rm -rf {} +
```

## 2.1 Включи нужный профиль и размер кластера

Файл: `.env` (из `.env.example`)

Минимум для переключения:

- `K8S_BOX_CLUSTER_PROFILE=test|dev|prod`
- `K8S_BOX_CLUSTER_NAME=<name>`
- `K8S_BOX_SUBNET_CIDR=<cidr>`
- `K8S_BOX_NODE_CORES`, `K8S_BOX_NODE_MEMORY_GB`, `K8S_BOX_NODE_BOOT_DISK_GB`
- `K8S_BOX_WORKER_MIN`, `K8S_BOX_WORKER_MAX`, `K8S_BOX_WORKER_INITIAL`

Если нужно полностью вручную задать node groups — используй `K8S_BOX_NODE_GROUPS_JSON`.

Если используешь готовый profile-файл, проверь его отдельно:

```bash
./scripts/validate-profile-file.sh profiles/test-minimal.env
```

## 3. Задай токен для Terraform/Terragrunt

```bash
source <(./scripts/refresh-yc-token.sh)
```

Если `yc` не настроен, задай токен вручную:

```bash
fresh_token="<your_token>"
export TF_VAR_YC_TOKEN="$fresh_token"
export TF_VAR_yc_token="$fresh_token"
export YC_TOKEN="$fresh_token"
```

Важно: не храни устаревший токен в `.env`.  
`bootstrap-k8s-box.sh` по умолчанию сам обновляет IAM-токен через `yc iam create-token` на каждом запуске.

## 3.1 Проверь `.env` перед запуском

```bash
./scripts/check-env.sh
```

Скрипт проверит обязательные переменные и остановит запуск, если найдены пустые/`CHANGE_ME` значения.

Если на этом каталоге уже были зависания на `service account create` или `folder add-access-binding`,
сначала отдельно проверь YC IAM backend:

```bash
./scripts/bootstrap-k8s-box.sh preflight-iam
```

Если `test-cluster-k8s` падает на `AlreadyExists` по `yandex_iam_service_account.master` / `node_account`:

- сначала посмотри вывод `./scripts/bootstrap-k8s-box.sh preflight`:
  - он покажет, в какой `folder name/id` реально смотрит текущий state;
- если это тот же folder и в нем остались cluster service account, bootstrap теперь попытается автоматически переиспользовать их;
- default cluster service account names теперь включают и `folder_name`, и `cluster_name`, чтобы параллельные стенды в одном cloud, но в разных folders, не пересекались по именам;
- если ты реально хочешь второй независимый folder, одного изменения переменных недостаточно:
  - нужен отдельный state / отдельная копия `k8s-box`,
  - иначе текущий state продолжит работать с уже управляемым folder.

## 4. Запуск одной командой (рекомендуется)

```bash
./scripts/bootstrap-k8s-box.sh apply-cluster
```

Это создаст:

- folder в YC;
- VPC и subnet;
- security group;
- test Kubernetes cluster.

Если нужен полный стек (включая `vault-infra` и `argocd`), используй:

```bash
./scripts/bootstrap-k8s-box.sh apply
```

Для test-стенда внешний cloud LoadBalancer по умолчанию не нужен:

- профиль `test` теперь использует:
  - `K8S_BOX_ALLOW_PUBLIC_LOAD_BALANCERS=false`
  - `K8S_BOX_ENABLE_NLB_HC_RULE=false`
- доступ к UI и сервисам предполагается через:
  - `kubectl port-forward`
  - VPN VM
  - внутренние маршруты в контуре.

Важно по ArgoCD:

- в режиме `apply-cluster` ArgoCD **не** ставится;
- в режиме `apply` ArgoCD ставится, и скрипт перед модулем `argocd` автоматически подтягивает kube-context (`yc-<cluster_name>`).
- в режиме `apply` должен быть задан токен для Git-репозитория (`K8S_BOX_GITLAB_REPO_TOKEN` или `GITLAB_TOKEN`);
  скрипт автоматически читает его из `k8s-box/.env`, если файл существует.

## 5. Проверь кластер

```bash
kubectl get nodes
```

Если видишь ноды в `Ready`, кластер поднят.  
Если контекст не подхватился автоматически, выполни:

```bash
cd test-cluster-k8s
CLUSTER_ID="$(terragrunt output -raw cluster_id)"
cd ..
yc managed-kubernetes cluster get-credentials --id "$CLUSTER_ID" --external --force
```

## Опционально: ручной запуск по модулям

Если нужно запускать полностью вручную:

```bash
cd folder && terragrunt apply -auto-approve && cd ..
cd vpc && terragrunt apply -auto-approve && cd ..
cd security-group && terragrunt apply -auto-approve && cd ..
cd test-cluster-k8s && terragrunt apply -auto-approve && cd ..
```

## Что с prod?

Сейчас в этом репозитории есть модуль только для **test-кластера**: `test-cluster-k8s`.
Отдельного terragrunt-модуля для отдельного prod-кластера нет.

`test/prod` в `../infrastructure` — это профили приложений (Vault/Observability), а не создание разных кластеров.

## Опционально: пост-проверка после полного `apply`

После полного `./scripts/bootstrap-k8s-box.sh apply` можно запустить пост-проверку:

```bash
./scripts/platform-maintenance.sh upgrade-vault-observability
```
