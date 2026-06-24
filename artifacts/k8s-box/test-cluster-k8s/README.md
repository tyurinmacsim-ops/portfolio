# Модуль `test-cluster-k8s`

## Назначение
Terragrunt-слой для создания managed Kubernetes-кластера (test).

## Зависимости
- `../folder`
- `../vpc`
- `../security-group`

## Что делает
- Вызывает Terraform-модуль `../yc-k8s-module`.
- Создает кластер (по умолчанию `test-cluster`, Kubernetes `1.33`).
- Создает node groups из профиля (`profiles/cluster-profiles.hcl`) и env-overrides из `.env`.

## Вариативность
- Профиль: `K8S_BOX_CLUSTER_PROFILE=test|dev|prod`
- Ресурсы нод: `K8S_BOX_NODE_*`
- Масштаб: `K8S_BOX_WORKER_*`, `K8S_BOX_MONITORING_*`
- Полный кастом: `K8S_BOX_NODE_GROUPS_JSON` (JSON map node_groups)

## Основные команды
```bash
cd test-cluster-k8s
terragrunt plan
terragrunt apply
terragrunt destroy
terragrunt output
```

## Важно
- `cluster_id`/`cluster_name` используются для kubeconfig и последующего модуля `argocd`.
- Для доступа к кластеру:
```bash
yc managed-kubernetes cluster get-credentials --id "$(terragrunt output -raw cluster_id)" --external --force
```
