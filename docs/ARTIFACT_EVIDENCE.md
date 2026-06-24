# Дополнительные артефакты без git-истории

Этот раздел не смешивается с commit-графиками. Здесь вынесены рабочие материалы, у которых в локальном архиве нет читаемой `.git`-истории, но сама структура артефактов подтверждает тип задач и стек.

## Backup / Restore Automation Toolkit

- Источник: `/Users/macbook/Yandex.Disk.localized/работа/01.tech/sckript-program/db-backup`
- Тип подтверждения: non-git evidence по рабочему каталогу.
- Что подтверждает: практическую работу с backup/restore automation, Kubernetes CronJob, Dockerized utilities, S3/AWS, Secrets Manager, Slack alerting, PostgreSQL, MariaDB и MongoDB.
- Публичные redacted-копии в репозитории: [artifacts/backup-automation](../artifacts/backup-automation/README.md)

## Состав артефакта

- Python-скрипты: `3`
- Shell-скрипты: `6`
- YAML manifests: `15`
- Dockerfiles: `3`
- Env files: `3`
- Kustomize overlays: `2`

## Что видно по содержимому

- Python-скрипты реализуют backup и restore сценарии с логированием, Slack-оповещением и работой через AWS Secrets Manager / S3.
- В каталоге есть Kubernetes-манифесты для cron-based backup/restore джобов.
- Есть отдельные shell-сценарии для миграций и ручного экспорта баз.
- Это хороший артефакт не про «настроил кластер», а про эксплуатацию данных, резервное копирование и recovery-процессы.

## Ключевые файлы

- [backup-k8s/files/daily_backups_lambda.py](../artifacts/backup-automation/backup-k8s/files/daily_backups_lambda.py)
- [backup-k8s/files/restore_backups.py](../artifacts/backup-automation/backup-k8s/files/restore_backups.py)
- [backup-mongo-k8s/files/daily_backups_mongodb.py](../artifacts/backup-automation/backup-mongo-k8s/files/daily_backups_mongodb.py)

## K8s-box Platform Toolkit

- Источник: `/Users/macbook/Yandex.Disk.localized/работа/hilbert team/coretech/k8s-box`
- Тип подтверждения: sanitized public copy рабочего platform engineering toolkit.
- Что подтверждает: практическую работу с `Yandex Cloud`, `Terraform`, `Terragrunt`, `ArgoCD`, `Vault`, `GitLab CI/CD`, VPN entrypoint, cluster profiles и эксплуатационной документацией.
- Публичная копия в репозитории: [artifacts/k8s-box](../artifacts/k8s-box/README.md)
- Состав публичной копии: `136` файлов, включая `50` Terraform-файлов, `20` shell-скриптов, `10` HCL-файлов и `31` Markdown-документ.
- Что было исключено из публичной копии: `.git`, `.env`, `.generated`, клиентские VPN-конфиги, дублирующие рабочие каталоги и соседний runtime-репозиторий `infrastructure`.

## Следующие артефакты, которые можно публиковать в redacted-виде

Ниже перечислены не исходные рабочие репозитории, а типы технических артефактов, которые можно безопасно вынести в публичное портфолио после обезличивания.

### 1. GitLab CI template bundle

- Что можно показать: reusable `.gitlab-ci` templates для `docker build/push`, manual jobs, release rules, job inheritance через `extends`.
- Что это подтверждает: практическую работу с `GitLab CI/CD`, шаблонизацией пайплайнов, сборкой контейнеров и регламентом выкладки.
- Что обязательно вычищать: имена сервисов, registry paths, project labels, внутренние runner tags, URL и внутренние naming conventions.

### 2. Vault + Kubernetes secret delivery bundle

- Что можно показать: `SecretProviderClass`, service account binding, pod manifests для `Vault CSI` / injector, а также обезличенный `Terraform`-lab для `Yandex Cloud Kubernetes`.
- Что это подтверждает: работу с `Vault`, `Kubernetes`, `CSI`, service accounts, IaC и доставкой секретов в workload.
- Что обязательно вычищать: реальные secret paths, namespace naming, cloud IDs, `.env`, `.tfstate`, сертификаты, PDF-материалы и любые внутренние инструкции.

### 3. Helm observability bundle

- Что можно показать: redacted `values.yaml`, `Chart.yaml`, exporter configs, service monitor patterns, security context и типовые настройки для monitoring stack.
- Что это подтверждает: практическую работу с `Helm`, `Prometheus` ecosystem, exporters, chart values и эксплуатационной конфигурацией Kubernetes-сервисов.
- Что обязательно вычищать: домены, внутренние endpoints, tenant naming, alert routing details и любые кастомные интеграции, ведущие на внутренние системы.

### 4. Terraform / Ansible infrastructure patterns

- Что можно показать: обезличенные модули, сетевые шаблоны, node group definitions, inventory patterns, bootstrap logic.
- Что это подтверждает: `Terraform`, `Terragrunt`, `Ansible`, сетевую и кластерную автоматизацию, повторяемые инфраструктурные паттерны.
- Что обязательно вычищать: state files, inventories с IP/FQDN, client/resource names, IAM identities, backend-конфигурацию и provider credentials.

## Что принципиально не публикуется

- чужая commit-история и авторство других инженеров;
- клиентские названия проектов, домены, namespaces и registry paths;
- `.env`, `.tfstate`, kubeconfig, inventories, сертификаты и access-данные;
- внутренние презентации, PDF, runbooks и документы, по которым можно восстановить контекст заказчика;
- полный рабочий репозиторий, если его ценность для портфолио можно показать через 2-5 обезличенных файлов.
