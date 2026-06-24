# Backup Automation Evidence

Публичный набор redacted-копий рабочих automation-артефактов по резервному копированию и восстановлению данных.

Что здесь важно:

- это не учебные примеры с нуля, а обезличенные публичные версии рабочих скриптов;
- приватные идентификаторы, внутренние имена и детали окружений убраны;
- логика сохранена: `AWS S3`, `Secrets Manager`, `Slack alerting`, `PostgreSQL`, `MariaDB`, `MongoDB`, `Kubernetes CronJob`, shell-based dump/restore pipelines.

Структура:

- [backup-k8s/files/daily_backups_lambda.py](backup-k8s/files/daily_backups_lambda.py)
- [backup-k8s/files/restore_backups.py](backup-k8s/files/restore_backups.py)
- [backup-mongo-k8s/files/daily_backups_mongodb.py](backup-mongo-k8s/files/daily_backups_mongodb.py)

Что это подтверждает:

- эксплуатацию stateful сервисов, а не только CI/CD и деплой;
- работу с recovery workflows и проверкой восстановления;
- умение собирать операционный контур вокруг дампов, шифрования, хранения и оповещений.
