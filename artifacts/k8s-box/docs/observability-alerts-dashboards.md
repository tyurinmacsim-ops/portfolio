# Observability: алерты и дашборды

Документ описывает базовый набор алертов и дашбордов для поддерживаемых стеков:

- `vm-loki-grafana` (VictoriaMetrics + Loki + Grafana)
- `prom-loki-grafana` (kube-prometheus-stack + Loki + Grafana)

## 1. Источники шаблонов

Шаблоны хранятся в Argo/GitOps-репозитории `infrastructure`:

- `infrastructure/observability/manifests/grafana-dashboards/configmap-dashboards.yaml`
- `infrastructure/observability/manifests/grafana-dashboards/dashboards-json/*`

Основаны на существующих практиках из твоих репозиториев:

- `vipservice/argocd/.../tenants/infra/monitoring/values.yaml`
- `vipservice/argocd/.../tenants/infra/monitoring/templates/configmap-dashboards.yaml`
- `rnd-argocd/.../infra-apps/loki/values-loki.yaml`
- `rnd-argocd/.../infra-apps/victoria-metrics/values/values.yaml`

## 2. Базовые алерты

Alerting настраивается в зависимости от выбранного стека:

- `vm-loki-grafana`: блок `alertmanager` в `observability/manifests/victoria/victoria-metrics-k8s-stack.values.yaml`.
- `prom-loki-grafana`: блок `alertmanager` в `observability/manifests/prometheus/kube-prometheus-stack.values.yaml`.
Базовые типы правил:

- `NodeCpuHigh` — высокая CPU-нагрузка нод.
- `NodeMemoryHigh` — высокая memory-нагрузка нод.
- `PodRestartsHigh` — частые перезапуски контейнеров.
- `PVUsageHigh` — высокая утилизация persistent volumes.

Рекомендация для production:

- Разделить каналы Telegram по `severity`/`team`.
- Добавить URL руководства в `annotations` правил.
- Вынести `bot_token`/`chat_id` в секреты (SOPS/Vault/ExternalSecrets).

В текущем шаблоне токен Telegram берется из Kubernetes Secret `alertmanager-telegram-bot` через `bot_token_file`.

## 3. Базовые дашборды

Подготовлены JSON-дашборды:

- `Kubernetes/cluster-overview.json`
- `Kubernetes/nodes-overview.json`
- `Kubernetes/kubernetes-objects.json`
- `Services/key-services.json`

Они покрывают:

- кластерный обзор;
- состояние и загрузку нод;
- Kubernetes-объекты (deployment/pod restarts);
- ключевые сервисные метрики (RPS, HTTP 5xx).

## 4. Подключение к Grafana

Используй `infrastructure/observability/manifests/grafana-dashboards/configmap-dashboards.yaml`.

Требования:

- dashboards с лейблом `grafana_dashboard: "1"`;
- sidecar dashboards в Grafana включен;
- папка в Grafana задается через `grafana-dashboard-folder` annotation.

## 5. Проверка после внедрения

1. Проверить scrape targets: vmagent должен видеть kube-state-metrics, node-exporter, приложения.
2. Проверить ingestion логов: Loki получает логи со всех нод.
3. Проверить ретеншн и PVC/S3-хранилище.
4. Сгенерировать тестовый alert и убедиться в доставке в Telegram.
5. Проверить, что все 4 базовых dashboard отображают данные.

## 6. Как внедрять через ArgoCD

1. Обновить плейсхолдеры `CHANGE_ME_*` в values стека.
2. Настроить и применить `infrastructure/observability/manifests/external-secrets/monitoring-alertmanager-telegram-bot.yaml`.
   В backend секрета ожидается ключ `telegram_bot_token`.
3. Добавить dashboard ConfigMap на основе `infrastructure/observability/manifests/grafana-dashboards/configmap-dashboards.yaml` и JSON-файлов из `infrastructure/observability/manifests/grafana-dashboards/dashboards-json`.
4. Проверить health/sync в ArgoCD и статус pod-ов в namespace `monitoring`.

## 7. Чеклист плейсхолдеров

- `CHANGE_ME_CLUSTER_SECRET_STORE` — имя `ClusterSecretStore` для External Secrets.
- `CHANGE_ME_ALERTMANAGER_SECRET_PATH` — путь в secret backend до объекта с `telegram_bot_token`.
- `CHANGE_ME_TELEGRAM_WARNING_CHAT_ID` — Telegram chat id для warning алертов.
- `CHANGE_ME_TELEGRAM_CRITICAL_CHAT_ID` — Telegram chat id для critical алертов.
- `CHANGE_ME_STORAGE_CLASS` — storage class для PVC компонентов стека.
- `CHANGE_ME_CLUSTER_NAME` — имя/лейбл кластера для метрик и логов.
- `CHANGE_ME_GRAFANA_ADMIN_PASSWORD` — admin password Grafana в values выбранного стека.
