# Внутренний инфраструктурный конвейер (Hilbert)

Документ описывает внутренний процесс для команды: от пустого аккаунта клиента в Yandex Cloud до автоматического развертывания через GitLab CI.

## 1. Цель

1. Получить вводные по клиенту.
2. Подготовить стек `k8s-box` под эти вводные.
3. Прогнать `plan` на коммитах.
4. Выполнять `apply` после merge в `main`.

## 2. Базовая схема

1. Пустой аккаунт клиента в YC.
2. Поднимаем VPN VM (опционально, как точку входа в private инфраструктуру).
3. Поднимаем отдельную VM под `infra-runner` (вне целевого Kubernetes).
4. Регистрируем runner в GitLab с тегом `infra-runner`.
5. Подключаем репозиторий `k8s-box` с новым `.gitlab-ci.yml`.
6. На push/MR получаем `plan`.
7. На merge в `main` автоматически выполняется `apply`.

Для переключения observability-инструментов между релизами используй:

```bash
./scripts/set-observability-stack.sh vm-loki-grafana --profile test
# или
./scripts/set-observability-stack.sh prom-loki-grafana --profile test
# или
./scripts/set-observability-stack.sh vm-loki-grafana --profile prod --secret-provider vso
```

Важно: runner не должен зависеть от разворачиваемого кластера, иначе процесс начальной установки ломается.

Важно и для CI-потока:

- runner checkout-ит только `k8s-box`;
- соседний GitOps-репозиторий `infrastructure` pipeline теперь подтягивает сам;
- runtime-вариант Vault/Observability задается CI variables, а не ручной правкой файлов на runner VM.
- несекретную конфигурацию лучше передавать не десятками CI variables, а одним profile-файлом:
  - например `K8S_BOX_PROFILE_FILE=profiles/test-minimal.env`;
  - секреты при этом остаются в GitLab CI variables.

Быстрый запуск runner кодом:

```bash
./scripts/bootstrap-k8s-box.sh apply-runner
```

Для `apply-runner` обязательно задать:

1. `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN` (или `K8S_BOX_GITLAB_RUNNER_TOKEN`)
2. `K8S_BOX_GITLAB_URL` (или `K8S_BOX_GITLAB_API_URL`)

Быстрый запуск VPN VM кодом:

```bash
./scripts/bootstrap-k8s-box.sh apply-vpn
./scripts/vpn-smoke-check.sh
```

## 3. Опросник (вводные по клиенту)

Источник данных: [profiles/cluster-requirements.example.env](../profiles/cluster-requirements.example.env)

Минимальные поля:

1. `CLOUD_ID`
2. `FOLDER_NAME`
3. `NETWORK_NAME`
4. `CLUSTER_NAME`
5. `YC_ZONE`
6. `SUBNET_CIDR`
7. `ESTIMATED_APP_PODS`
8. `AVG_POD_CPU_M`
9. `AVG_POD_MEM_MIB`
10. `K8S_BOX_GITLAB_*` параметры доступа к GitOps

После заполнения:

```bash
./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<client>-<env>.env \
  --validate-only

./scripts/scaffold-stack-from-requirements.sh \
  --requirements ./profiles/<client>-<env>.env \
  --output ../k8s-box-<client>-<env>
```

Если используется готовый profile-файл из репозитория, его также стоит проверить отдельно:

```bash
./scripts/validate-profile-file.sh profiles/test-minimal.env
```

Опросник по сбору вводных: [customer-requirements-questionnaire.md](./customer-requirements-questionnaire.md)

## 4. Начальная установка runner

Используй шаблон cloud-init:

- [runner/cloud-init-gitlab-runner.yaml.tpl](../runner/cloud-init-gitlab-runner.yaml.tpl)

Минимум, что должно быть на runner:

1. `terraform`
2. `terragrunt`
3. `yc`
4. `kubectl`
5. `helm`
6. `jq`

Runner tag в GitLab: `infra-runner`.

## 5. CI-поведение

Конвейер в `k8s-box/.gitlab-ci.yml`:

1. `validate:*` — проверки shell/hcl и окружения инструментов.
   - сюда же входит проверка встроенных profile-файлов и выбранного `K8S_BOX_PROFILE_FILE`.
2. `plan:*` — запускается на push/MR только при изменениях в соответствующих директориях.
   - В job-артефактах сохраняются:
     - полный лог (`plan-*.log`),
     - очищенный от ANSI лог (`plan-*.clean.log`),
     - краткая выжимка (`plan-*.summary`).
3. `apply:*` — запускается на push в `main` (после merge) и применяет изменения.
4. `verify:*` — health/smoke после apply.
5. `destroy:stack` — только manual job.

Перед `plan/apply/verify` platform-стадий pipeline выполняет:

1. `./scripts/ensure-infra-repo.sh`
2. `./scripts/apply-platform-runtime-profile.sh`

## 6. Переменные GitLab CI

### 6.1 Обязательные секреты

1. `YC_TOKEN` или `TF_VAR_YC_TOKEN`
2. `K8S_BOX_GITLAB_REPO_USER`
3. `K8S_BOX_GITLAB_REPO_TOKEN` (или `GITLAB_TOKEN`)
4. `K8S_BOX_GITLAB_API_URL`
5. `K8S_BOX_GITLAB_GROUP_PATH`
6. `K8S_BOX_GITLAB_SUBGROUP`
7. `K8S_BOX_STATIC_GIT_REPO_BASE_URL`
8. `ARGOCD_ADMIN_PASSWORD`
9. `K8S_BOX_INFRA_REPO_REF` (если нужен не `main`)

### 6.2 Несекретная конфигурация

Рекомендуемый вариант:

1. `K8S_BOX_PROFILE_FILE`

Например:

- `profiles/test-minimal.env`
- `profiles/dev-standard.env`
- `profiles/prod-baseline.env`

Переопределять отдельные переменные поверх profile-файла имеет смысл только для точечных исключений.

Примечание по `YC_TOKEN`/`TF_VAR_YC_TOKEN`:

- базовый вариант: хранить как protected/masked CI variable;
- альтернативный вариант: не хранить токен в GitLab, если runner VM имеет Service Account с нужными ролями и может получить токен через metadata (`yc iam create-token`).

## 7. Оценка по времени (быстрый ориентир)

1. Новый клиент, пустой YC аккаунт, runner еще нет: 1-2 рабочих дня.
2. Runner уже есть, вводные полные: 4-8 часов до первого успешного deploy.
3. Изменения только values/профилей observability/vault: 1-3 часа.

Это ориентир для пресейла; финальная оценка зависит от сетевых ограничений, VPN, IAM и требований по безопасности.
