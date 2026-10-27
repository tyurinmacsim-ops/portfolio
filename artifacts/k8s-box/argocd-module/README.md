# Terraform-модуль `argocd-module`

## Назначение
Установка ArgoCD (через Helm) и базовая GitOps-конфигурация репозиториев/приложений.

## Основные возможности
- Установка `argo-cd` chart.
- Генерация репозиторных credentials для GitOps.
- Создание `argocd-admin-credentials` (опционально).
- Настройка `argocd-apps` (проекты и applicationsets).

## Ключевые переменные
- GitLab/static repo:
  - `manage_gitlab`
  - `gitlab_api_url`
  - `static_git_repo_base_url`
  - `static_git_repo_username`
  - `static_git_repo_password`
- ArgoCD:
  - `argocd_helm_release_*`
  - `argocd_admin_password`
  - `argocd_set_admin_user_password`
- Проекты:
  - `projects`

## Где используется
- Terragrunt-слой: `k8s-box/argocd/terragrunt.hcl`.

## Важно
- Для static-режима обязательно передавать непустой токен (`static_git_repo_password`), иначе ArgoCD может упасть на этапе рендера secret.
