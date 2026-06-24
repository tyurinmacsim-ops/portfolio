# Стратегия обновлений и сопровождения платформы (P7)

Документ описывает стратегию обновлений и регламентные операции для:

1. Kubernetes кластера,
2. ArgoCD,
3. infra-сервисов (Vault + Observability).

## 1. Принципы

1. Любые изменения идут через код и MR.
2. Для каждого слоя есть отдельные precheck/plan/apply шаги.
3. После каждого изменения запускается единый health-check.
4. Ручные runtime-фиксы не считаются завершением: фикс должен быть зафиксирован в Git.

## 2. Слои обновлений

### Kubernetes

Модуль: `k8s-box/test-cluster-k8s`.

Обновляется через:

```bash
./scripts/platform-maintenance.sh plan-k8s
./scripts/platform-maintenance.sh apply-k8s
```

### ArgoCD

Модуль: `k8s-box/argocd`.

Обновляется через:

```bash
./scripts/platform-maintenance.sh plan-argocd
./scripts/platform-maintenance.sh apply-argocd
```

### Vault Infra (KMS/backup infra)

Модуль: `k8s-box/vault-infra`.

Обновляется через:

```bash
./scripts/platform-maintenance.sh plan-vault-infra
./scripts/platform-maintenance.sh apply-vault-infra
```

### Infra-сервисы (Vault + Observability через ArgoCD)

```bash
./scripts/set-vault-profile.sh prod --enable-backup-manifests true
./scripts/platform-maintenance.sh upgrade-vault-observability
./scripts/set-observability-stack.sh vm-loki-grafana --profile prod --secret-provider vso
```

## 3. Регламентные операции

### Ежедневно (или перед окном изменений)

1. Проверка состояния Argo app.
2. Проверка, что Vault initialized/unsealed.
3. Проверка стека мониторинга (`monitoring-*` apps + pods).
4. Дымовая проверка доступности web/API сервисов.

Команда:

```bash
./scripts/platform-maintenance.sh status
./scripts/platform-maintenance.sh smoke-services
```

### Еженедельно

1. Проверка preflight (особенно если менялись профили/values).
2. Проверка backlog обновлений Kubernetes/Argo chart versions.
3. Проверка руководств и актуальности шагов отката.

## 4. Конвейер (отдельный runner)

Требование: GitLab runner на отдельной VM с tag `infra-runner`, установленными:

1. `terragrunt`
2. `terraform`
3. `kubectl`
4. `helm`
5. `jq`

Файл конвейера:

1. `k8s-box/.gitlab-ci.yml`

Режим работы:

1. На `push`/`merge_request` запускается `plan` для измененных директорий.
2. На `push` в `main` (после merge) запускается `apply`.
3. После `apply` автоматически запускаются `verify` проверки.
4. `destroy` остается manual.

Важно:

- вариативность runtime-сервисов лучше держать в коде (`values.yaml` + `set-observability-stack.sh`), а не в веб-интерфейсе;
- pipeline должен применять уже согласованный вариант, а не быть единственным местом, где "живет" выбор инженера.

## 5. Выкатка/откат

### Выкатка

1. Commit/MR: проверяем `plan` job.
2. Слияние в `main`: автоматический `apply`.
3. Проверяем `verify` job.

### Откат

1. `git revert` проблемного коммита.
2. Слияние MR с откатом.
3. Повторный запуск `deploy` + `verify`.

### Полная очистка / повторное развертывание (для диагностики)

Если нужно полностью удалить Vault/Observability namespace и поднять заново через код:

```bash
./scripts/redeploy-gitops-apps.sh wipe
```

## 6. DoD-мэппинг по пункту 7

1. Стратегия обновлений описана для Kubernetes, ArgoCD, infra-сервисов.
2. Ручные операции сокращены за счет `platform-maintenance.sh`.
3. Регламентные проверки стандартизированы (`preflight`, `status`, `healthcheck`).
4. Конвейер вынесен в код и готов к запуску на отдельном infra-runner.
