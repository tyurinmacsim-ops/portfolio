# Руководство Vault + Observability (P5/P6)

Документ фиксирует воспроизводимый сценарий для пунктов:

- 5. HashiCorp Vault
- 6. Observability / Monitoring

## 1. Архитектура и зависимости

1. `k8s-box` поднимает Kubernetes и ArgoCD.
2. `infrastructure` репозиторий разворачивает через ArgoCD:
- `vault` приложение.
- `monitoring-*` приложения (в зависимости от `observabilityStack`: VictoriaMetrics или kube-prometheus-stack, плюс Loki/Grafana и выбранный провайдер секрета `vso|external-secrets|manual`).

Критичные зависимости:

1. ArgoCD должен быть `Healthy`.
2. Для `prod` профилей обязательна замена всех плейсхолдеров `CHANGE_ME*`.
3. Для `Vault prod` обязательны рабочие KMS/TLS/backup секреты.

## 2. Профили окружений

### test (для слабого кластера)

- Vault: standalone, минимальные ресурсы, без ingress.
- Observability: облегченный стек, без alertmanager/vmalert, синхронизация Telegram-секрета по умолчанию отключена.
- Backup-manifests Vault по умолчанию отключены.

### prod

- Vault: HA raft (base values), autounseal KMS, backup cronjob.
- Observability: полный профиль, способ доставки Telegram-секрета выбирается через `alertmanagerTelegram.secretProvider`.

## 3. Модель секретов и ротация

1. **ArgoCD admin**
- Источник: Terraform variable `ARGOCD_ADMIN_PASSWORD`.
- Хранение: bcrypt-хэш в `argocd-secret`, bootstrap secret `argocd-admin-credentials`.
- Ротация: смена `ARGOCD_ADMIN_PASSWORD` + `terragrunt apply` модуля `argocd`.

2. **Vault (prod)**
- `vault-kms-creds`, `vault-tls`, `vault-upstream-ca`, `vault-backup-token` хранятся в Kubernetes Secret.
- Ротация:
  - `vault-kms-creds`: ротация SA key в Yandex Cloud + обновление Kubernetes Secret.
  - TLS secrets: обновление сертификатов + rolling restart.
  - backup token: выпуск нового токена Vault и обновление `vault-backup-token`.

3. **Observability Telegram token**
- Источник задается выбранным провайдером:
  - `vso`: Vault Secrets Operator читает секрет из Vault;
  - `external-secrets`: External Secrets Operator читает секрет из внешнего backend;
  - `manual`: секрет `alertmanager-telegram-bot` создается вручную.
- Kubernetes хранит только materialized secret `alertmanager-telegram-bot`.
- Ротация:
  - `vso`: обновление в Vault, VSO подтянет автоматически;
  - `external-secrets`: обновление во внешнем backend, ESO подтянет автоматически;
  - `manual`: ручное обновление Kubernetes Secret.

4. **Grafana admin**
- Источник: values (`grafana.adminUser/adminPassword`) в `infrastructure` repo.
- Для prod рекомендуемо перейти на ESO/SOPS и не хранить password в открытом values.
- Ротация: обновление значения + Argo sync.

## 4. Первичный запуск (с нуля до `Healthy`)

1. Проверить профили и плейсхолдеры:

```bash
cd k8s-box
./scripts/preflight-vault-observability.sh
```

2. Выполнить чистый redeploy:

```bash
./scripts/redeploy-gitops-apps.sh redeploy
```

По умолчанию `redeploy-gitops-apps.sh` теперь не только пересоздает app, но и:

- ждет `Synced/Healthy` по родительским и ожидаемым дочерним app;
- для `vault profile=test` запускает idempotent bootstrap;
- один раз делает повторный `hard refresh + sync` для app, которые не вышли в ready;
- завершает работу `healthcheck-vault-observability.sh`.

Для полного удаления namespace и форсированного cleanup finalizers:

```bash
./scripts/redeploy-gitops-apps.sh wipe
```

3. Для test-профиля Vault (если auto-bootstrap выключен или не сработал):

```bash
./scripts/vault-test-bootstrap.sh
```

4. Проверить итог:

```bash
./scripts/healthcheck-vault-observability.sh
```

Если `healthcheck` падает на `monitoring-*`, сначала смотри начало вывода:

- `[CHECK] nodes ready=X/Y` показывает, есть ли вообще `Ready` worker-ноды;
- для `Pending` pod теперь печатаются причины `PodScheduled=False` и последние `FailedScheduling` events;
- на однонодовом test-кластере `NodeNotReady` быстро маскируется под симптомы вида `monitoring-loki Progressing` или `vm-stack OutOfSync`.

Критерий успешности:

- Argo apps `infrastructure-vault`, `infrastructure-observability`, `monitoring-*` в `Synced/Healthy`.
- Vault initialized/unsealed.
- Для `vault` в `test` допускается `OutOfSync/Healthy` (контролируется отдельным warning из healthcheck).

## 5. Процедура обновления

1. Обновить chart version/values в `infrastructure`:
- `vault/values.yaml` (`vaultChartVersion`, profile values).
- `observability/values.yaml` (chart versions/profile flags).

2. Прогнать preflight:

```bash
./scripts/preflight-vault-observability.sh
```

3. Закоммитить и запушить изменения.
4. В ArgoCD дождаться sync/health.
5. Прогнать healthcheck:

```bash
./scripts/healthcheck-vault-observability.sh
```

## 6. Процедура восстановления

### Vault test

1. Проверить статус:

```bash
kubectl -n vault exec vault-0 -- vault status
```

2. Выполнить idempotent bootstrap:

```bash
./scripts/vault-test-bootstrap.sh
```

### Vault prod

1. Проверить raft peers и seal status.
2. При потере данных восстановить из snapshot (`vault operator raft snapshot restore`).
3. Проверить auth mounts/policies и доступ приложений.

### Observability

1. Проверить `monitoring-*` apps в Argo.
2. Проверить pods в `monitoring`.
3. Проверить `kubectl get nodes`:
   - если `Ready`-нод нет или единственная node в `NotReady`, проблема не в values `Loki/Victoria`, а в состоянии worker node / autoscaler.
4. Если pod в `Pending`, смотреть `FailedScheduling` перед повторным redeploy.
5. Для `external-secrets` проверить `ClusterSecretStore` и `ExternalSecret`.
6. Для `vso` проверить `VaultAuth`, `VaultConnection`, `VaultStaticSecret`.

## 7. Процедура отката

1. Откатить problematic commit в `infrastructure` (`git revert` или checkout предыдущего тега).
2. Запушить rollback commit.
3. Дождаться Argo sync.
4. Прогнать healthcheck:

```bash
./scripts/healthcheck-vault-observability.sh
```

## 8. DoD Checklist (P5/P6)

1. `preflight-vault-observability.sh` проходит.
2. `redeploy-gitops-apps.sh redeploy` выполняется без ручного вмешательства.
3. `vault-test-bootstrap.sh` идемпотентен (повторный запуск безопасен).
4. `healthcheck-vault-observability.sh` дает `OK` (допускается warning только при явно разрешенном режиме).
5. Документация по процессам deploy/upgrade/recovery/rollback актуальна.

## 9. Только ручные команды (без вспомогательных скриптов)

Минимальный набор команд для полного ручного цикла.

### 9.1 Удаление

```bash
kubectl -n argocd delete application \
  vault monitoring-vault-secrets-operator monitoring-external-secrets-operator \
  monitoring-alertmanager-vault-secrets monitoring-alertmanager-external-secrets \
  monitoring-victoria-metrics-stack monitoring-kube-prometheus-stack monitoring-loki \
  --ignore-not-found --wait=false

kubectl delete namespace vault monitoring external-secrets vault-secrets-operator-system --ignore-not-found --wait=false
```

### 9.2 Очистка finalizer (если нужно)

```bash
for ns in monitoring external-secrets vault-secrets-operator-system; do
  kubectl get namespace "$ns" -o json \
    | jq '.spec.finalizers=[]' \
    | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f -
done
```

### 9.3 Пересоздание и синхронизация

```bash
kubectl create namespace vault || true
kubectl create namespace monitoring || true
kubectl create namespace external-secrets || true
kubectl create namespace vault-secrets-operator-system || true

kubectl -n argocd annotate application infrastructure-vault argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd patch application infrastructure-vault --type merge \
  -p '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true"]}}}'

kubectl -n argocd annotate application infrastructure-observability argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd patch application infrastructure-observability --type merge \
  -p '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true"]}}}'
```

### 9.4 Vault init/unseal (test)

```bash
kubectl -n vault exec vault-0 -- vault operator init -format=json > ~/.k8s-box/vault/test-init.json
chmod 600 ~/.k8s-box/vault/test-init.json

for i in 0 1 2; do
  key=$(jq -r ".unseal_keys_b64[$i]" ~/.k8s-box/vault/test-init.json)
  kubectl -n vault exec vault-0 -- vault operator unseal "$key"
done
```

### 9.5 Проверка

```bash
kubectl -n argocd get applications
kubectl -n vault exec vault-0 -- vault status
kubectl -n monitoring get pods
```
