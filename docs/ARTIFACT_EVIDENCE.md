# Дополнительные артефакты без git-истории

Этот раздел не смешивается с commit-графиками. Здесь вынесены рабочие материалы, у которых в локальном архиве нет читаемой `.git`-истории, но сама структура артефактов подтверждает тип задач и стек.

## Backup / Restore Automation Toolkit

- Источник: `/Users/macbook/Yandex.Disk.localized/работа/01.tech/sckript-program/db-backup`
- Тип подтверждения: non-git evidence по рабочему каталогу.
- Что подтверждает: практическую работу с backup/restore automation, Kubernetes CronJob, Dockerized utilities, S3/AWS, Secrets Manager, Slack alerting, PostgreSQL, MariaDB и MongoDB.

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

- `backup-k8s/files/daily_backups_lambda.py`
- `backup-k8s/files/restore_backups.py`
- `backup-mongo-k8s/files/daily_backups_mongodb.py`
