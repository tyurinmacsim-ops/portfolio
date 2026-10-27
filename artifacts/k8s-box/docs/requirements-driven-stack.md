# Руководство: стек из требований заказчика

Цель: собрать отдельный `k8s-box` стек с отдельным `state` под конкретного заказчика без ручного копирования всех настроек по модулям.

Сценарий использования такой:

1. инженер собирает вводные по проекту;
2. инженер оценивает требования к сети, доступам, отказоустойчивости и нагрузке;
3. генератор помогает быстро подготовить стартовую конфигурацию;
4. итоговый профиль и параметры при необходимости уточняются инженером.

## 1. Что делает генератор

Скрипт `scripts/scaffold-stack-from-requirements.sh`:

1. Читает файл требований (`.env`-формат).
2. Считает стартовый размер worker-группы по CPU/Memory (из pod-нагрузки).
3. Создает отдельный стек (отдельный `state`).
4. Генерирует параметризованные `terragrunt.hcl` для:
   - `vpc`
   - `security-group`
   - `test-cluster-k8s`
   - `vault-infra`
5. Генерирует `.env.example` с нужными переменными окружения.
6. Оставляет инженеру переключаемый runtime-слой:
   - Vault profile и backup-режим,
   - observability stack,
   - профиль observability,
   - способ доставки Telegram-секрета (`vso|external-secrets|manual`).

Важно: генератор не принимает архитектурное решение вместо инженера. Он ускоряет сборку стартового стека на основе уже собранных требований.

## 2. Подготовка requirements-файла

```bash
cd <path-to-coretech>/k8s-box
cp ./profiles/cluster-requirements.example.env ./profiles/<company>-<env>.env
```

Заполни минимум:

- идентификаторы/сеть: `STACK_NAME`, `CLOUD_ID`, `FOLDER_NAME`, `NETWORK_NAME`, `CLUSTER_NAME`, `YC_ZONE`, `SUBNET_CIDR`;
- нагрузку: `ESTIMATED_APP_PODS`, `AVG_POD_CPU_M`, `AVG_POD_MEM_MIB`;
- GitOps: `K8S_BOX_GITLAB_API_URL`, `K8S_BOX_GITLAB_GROUP_PATH`, `K8S_BOX_GITLAB_SUBGROUP`, `K8S_BOX_STATIC_GIT_REPO_BASE_URL`, `K8S_BOX_GITLAB_REPO_USER`.

Если инженер собирает вводные с нуля, используй опросник:

- [customer-requirements-questionnaire.md](./customer-requirements-questionnaire.md)

## 3. Вариативность (что переключается)

Поддерживается не только observability, но и базовая инфраструктура:

- кластер:
  - `CLUSTER_VERSION`, `RELEASE_CHANNEL`, `CNI_TYPE`
  - `PUBLIC_ACCESS`, `MASTER_PUBLIC_ACCESS`, `MASTER_AUTO_UPGRADE`
  - `ALLOW_PUBLIC_LOAD_BALANCERS`
- sizing и autoscaling:
  - `NODE_VCPU`, `NODE_MEMORY_GIB`, `NODE_BOOT_DISK_GB`
  - `WORKER_MIN`, `WORKER_MAX`
  - `ENABLE_MONITORING_NODE`, `MONITORING_MIN|MAX|INITIAL`
- сеть/доступ:
  - `API_ALLOWED_CIDRS`, `SSH_ALLOWED_CIDRS`
  - `ENABLE_NLB_HC_RULE`
  - `ENABLE_NODEPORT_RULE`, `NODEPORT_FROM`, `NODEPORT_TO`, `NODEPORT_ALLOWED_CIDRS`
- Vault infra:
  - `KMS_KEY_ROTATION_PERIOD`
  - `CREATE_BACKUP_BUCKET`, `BACKUP_BUCKET_NAME`
- Vault runtime:
  - `VAULT_PROFILE=test|prod`
  - `VAULT_ENABLE_BACKUP_MANIFESTS=true|false`
  - `VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST=true|false`
- Observability:
  - `OBSERVABILITY_STACK=vm-loki-grafana|prom-loki-grafana`
  - `OBSERVABILITY_PROFILE=test|dev|prod`
  - `OBSERVABILITY_SECRET_PROVIDER=vso|external-secrets|manual`
  - `OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST=true|false`

Важно:

- текущая генерация инфраструктуры рассчитана на `Yandex Cloud`;
- репозиторий поддерживает вариативность сценариев внутри `YC`, а не разные облака;
- для `test` разумный дефолт такой:
  - `ALLOW_PUBLIC_LOAD_BALANCERS=false`
  - `ENABLE_NLB_HC_RULE=false`
  - доступ к сервисам через `port-forward`/VPN, без внешнего LB.
- генератор стека использует именно такую логику по умолчанию:
  - для `ENVIRONMENT=test` эти два флага будут выключены, если их не задать явно;
  - для `dev/prod` останутся включенными.

## 4. Генерация стека

Сначала проверь входные данные без генерации каталога:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<company>-<env>.env \
  --validate-only
```

Скрипт выведет расчетный размер кластера и ключевые флаги профиля, не создавая новый stack.

Если результаты выглядят корректно, генерируй стек:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env>
```

Если каталог уже есть:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env> \
  --force
```

`--validate-only` полезен перед пресейлом и перед первым CI-запуском: он позволяет быстро увидеть, не включили ли в `test` лишние публичные LB, и не получился ли слишком слабый `prod`-профиль.

## 5. Заполнение рабочего `.env`

```bash
cd ../k8s-box-<company>-<env>
cp .env.example .env
```

Обязательно задать секреты и токены:

- `TF_VAR_YC_TOKEN` (или `YC_TOKEN`);
- `K8S_BOX_GITLAB_REPO_TOKEN` (или `GITLAB_TOKEN`);
- `ARGOCD_ADMIN_PASSWORD`.

При необходимости скорректируй runtime-варианты без ручной правки Helm values:

```bash
./scripts/set-vault-profile.sh \
  "$K8S_BOX_VAULT_PROFILE" \
  --enable-backup-manifests "$K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS" \
  --enable-backup-in-test "$K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST"

./scripts/set-observability-stack.sh \
  "$K8S_BOX_OBSERVABILITY_STACK" \
  --profile "$K8S_BOX_OBSERVABILITY_PROFILE" \
  --secret-provider "$K8S_BOX_OBSERVABILITY_SECRET_PROVIDER" \
  --enable-secret-sync-in-test "$K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST"

Или единым действием:

```bash
./scripts/apply-platform-runtime-profile.sh
```
```

Проверка:

```bash
./scripts/check-env.sh
./scripts/validate-profile-file.sh profiles/test-minimal.env
```

## 6. Развертывание

План:

```bash
./scripts/bootstrap-k8s-box.sh plan-cluster
./scripts/bootstrap-k8s-box.sh plan
```

Применение:

```bash
./scripts/bootstrap-k8s-box.sh apply
./scripts/set-vault-profile.sh \
  "$K8S_BOX_VAULT_PROFILE" \
  --enable-backup-manifests "$K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS" \
  --enable-backup-in-test "$K8S_BOX_VAULT_ENABLE_BACKUP_MANIFESTS_IN_TEST"
./scripts/set-observability-stack.sh \
  "$K8S_BOX_OBSERVABILITY_STACK" \
  --profile "$K8S_BOX_OBSERVABILITY_PROFILE" \
  --secret-provider "$K8S_BOX_OBSERVABILITY_SECRET_PROVIDER" \
  --enable-secret-sync-in-test "$K8S_BOX_OBSERVABILITY_ENABLE_SECRET_SYNC_IN_TEST"
```

## 7. Проверка результата

```bash
kubectl get nodes -o wide
kubectl get ns
kubectl -n argocd get applications
```

## 8. Удаление

```bash
SKIP_FOLDER_DESTROY=true ./scripts/bootstrap-k8s-box.sh destroy
```

Полное удаление вместе с folder:

```bash
SKIP_FOLDER_DESTROY=false ./scripts/bootstrap-k8s-box.sh destroy
```
