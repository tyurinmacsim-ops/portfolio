# Модуль `argocd`

## Назначение
Terragrunt-слой для установки и первичной конфигурации ArgoCD в Kubernetes-кластер.

## Зависимости
- `../test-cluster-k8s` (endpoint, cluster_name, CA).

## Что делает
- Вызывает Terraform-модуль `../argocd-module`.
- Устанавливает ArgoCD Helm-чарт.
- Настраивает Git-репозиторий инфраструктуры для GitOps.

## Требования перед запуском
- Должен существовать kube-context `yc-<cluster_name>`.
- Должны быть заданы:
  - `K8S_BOX_GITLAB_REPO_USER`
  - `K8S_BOX_GITLAB_REPO_TOKEN` (или `GITLAB_TOKEN`)
  - `ARGOCD_ADMIN_PASSWORD`
- Helm cache/config для этого стека изолированы в локальном каталоге `.helm/`, чтобы установка ArgoCD не зависела от пользовательского `helm repo add/update` на ноутбуке инженера.

## Основные команды
```bash
cd argocd
terragrunt plan
terragrunt apply
terragrunt destroy
```
