# Опросник по требованиям заказчика

Цель опросника: не просить заказчика “выбрать Kubernetes-кластер”, а собрать достаточные вводные, чтобы инженер предложил подходящий профиль и скорректировал его под проект.

## 1. Контекст проекта

Нужно собрать:

1. Название проекта и окружения (`test/dev/prod`).
2. Облако и каталог в `Yandex Cloud`.
3. Есть ли уже принятые ограничения по сети, зонам доступности, доступам и naming.

## 2. Нагрузка и размер кластера

Минимальный набор вопросов:

1. Сколько приложенческих pod ожидается одновременно?
2. Какой средний `requests.cpu` у одного pod?
3. Какой средний `requests.memory` у одного pod?
4. Есть ли пики нагрузки по времени суток или по релизам?
5. Допускается ли autoscaling или требуется фиксированный размер?

Эти ответы затем конвертируются в:

- `ESTIMATED_APP_PODS`
- `AVG_POD_CPU_M`
- `AVG_POD_MEM_MIB`
- `WORKER_MIN`
- `WORKER_MAX`
- `NODE_VCPU`
- `NODE_MEMORY_GIB`

## 3. Сеть и доступ

Нужно уточнить:

1. Нужен ли публичный `master endpoint`?
2. Нужны ли публичные `LoadBalancer`-сервисы?
3. С каких CIDR должен быть доступ к Kubernetes API?
4. С каких CIDR нужен SSH-доступ к VPN VM?
5. Нужен ли `NodePort` доступ вообще?

Это влияет на:

- `MASTER_PUBLIC_ACCESS`
- `ALLOW_PUBLIC_LOAD_BALANCERS`
- `API_ALLOWED_CIDRS`
- `SSH_ALLOWED_CIDRS`
- `ENABLE_NODEPORT_RULE`

## 4. Отказоустойчивость и критичность

Нужно понять:

1. Это тестовый стенд, dev-окружение или production?
2. Нужна ли отдельная monitoring node group?
3. Нужно ли минимум 2 worker-ноды постоянно?
4. Требуется ли backup для Vault?
5. Требуется ли более строгий baseline по доступам уже на первом запуске?

Это влияет на:

- выбор `K8S_BOX_CLUSTER_PROFILE`
- `ENABLE_MONITORING_NODE`
- `VAULT_PROFILE`
- `VAULT_ENABLE_BACKUP_MANIFESTS`

## 5. Платформенные сервисы

Нужно заранее согласовать:

1. Какой observability stack нужен:
   - `vm-loki-grafana`
   - `prom-loki-grafana`
2. Какой профиль observability нужен:
   - `test`
   - `dev`
   - `prod`
3. Какой способ доставки runtime-секретов нужен:
   - `vso`
   - `external-secrets`
   - `manual`

## 6. Что инженер делает после опросника

После сбора данных инженер:

1. Заполняет `profiles/cluster-requirements.example.env` под заказчика.
2. Проверяет входные данные через:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<company>-<env>.env \
  --validate-only
```

3. Генерирует отдельный стек:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<company>-<env>.env \
  --output ../k8s-box-<company>-<env>
```

4. При необходимости уточняет итоговый профиль вручную.

Вывод: заказчик дает вводные, а не “выбирает кластер”. Архитектурное решение и финальный профиль подтверждает инженер.
