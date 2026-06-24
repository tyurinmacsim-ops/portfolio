# Кейсы и результаты

## 1. Production GitOps / Kubernetes для multi-service продукта

- Контекст: продуктовый контур с `100+` микросервисами в production.
- Подтверждающие артефакты: коммиты в потоках `GitOps / FluxCD`, `ops`, `Helm releases`, `CI templates`.
- Что делал: сопровождение AWS-инфраструктуры, перенос части сервисов в Kubernetes, настройка GitLab CI/CD, GitOps, деплой-пайплайнов, мониторинга, логирования и сервисных интеграций.
- Что это доказывает: практическую работу с `Kubernetes`, `Helm`, `FluxCD`, `Ansible`, `Terraform`, `GitLab CI`, эксплуатацией сервисов и production-процессами.
- Результат: повышение частоты релизов, снижение доли ручных операций и улучшение эксплуатационной предсказуемости.

## 2. Azure / AKS / PCI DSS readiness

- Контекст: fintech-инфраструктура в Azure.
- Что делал: IaC на `Terraform/Terragrunt`, GitOps через `FluxCD + GitLab CI`, AKS node pools, autoscaling, network policies, private ingress, Key Vault, аудитный след.
- Что это доказывает: опыт не только deployment-задач, но и platform/security-oriented DevOps работы.
- Результат: подготовка инфраструктурного контура к внешнему аудиту, ускорение релизного цикла и снижение эксплуатационных рисков.

## 3. Yandex Cloud / аналитическая платформа

- Контекст: инфраструктура аналитической платформы в Yandex Cloud.
- Что делал: сопровождение Kubernetes-кластера, CI/CD и GitOps-процессов, эксплуатация Airflow / Trino / JupyterHub / GitLab Runner, работа с Vault / External Secrets, ingress, registry и observability.
- Что это доказывает: уверенную работу в облаке, платформенных сервисах и data-инфраструктуре.
- Результат: поддержка production/dev контуров, развитие платформы и снижение ручной нагрузки на сопровождение.

## 4. Backup / Restore automation toolkit

- Контекст: отдельный рабочий каталог с эксплуатационными артефактами по резервному копированию, восстановлению и миграции данных.
- Подтверждающие артефакты: Python-скрипты `daily_backups_lambda.py`, `restore_backups.py`, `daily_backups_mongodb.py`, Kubernetes manifests для cron-based backup/restore задач, Dockerfiles и shell-сценарии экспорта.
- Что делал: автоматизация backup/restore контуров для PostgreSQL, MariaDB и MongoDB, интеграция с `AWS S3`, `Secrets Manager`, `Slack`-оповещением и Kubernetes CronJob.
- Что это доказывает: опыт не только в CI/CD и k8s delivery, но и в data operations, backup policy, recovery workflow и эксплуатационных сценариях вокруг stateful сервисов.
- Результат: отдельный воспроизводимый слой доказательств по backup automation, даже там, где в архиве не сохранилась читаемая git-история.
