# Кейсы и результаты

## 1. GitOps и Kubernetes для многосервисного продукта

- Контекст: продуктовый контур с `100+` микросервисами в production.
- Подтверждающие артефакты: коммиты в потоках `GitOps / FluxCD`, `ops`, `Helm releases`, `CI templates`.
- Что делал: сопровождение AWS-инфраструктуры, перенос части сервисов в Kubernetes, настройка GitLab CI/CD, GitOps, деплой-пайплайнов, мониторинга, логирования и сервисных интеграций.
- Что это доказывает: практическую работу с `Kubernetes`, `Helm`, `FluxCD`, `Ansible`, `Terraform`, `GitLab CI`, эксплуатацией сервисов и production-процессами.
- Результат: повышение частоты релизов, снижение доли ручных операций и улучшение эксплуатационной предсказуемости.

## 2. Массовые Telegram-рассылки / большие очереди

- Контекст: Telegram-платформа с `100+` микросервисами и асинхронными контурами массовой доставки сообщений.
- Что важно уточнить: это не кейс про десятки тысяч входящих `HTTP RPS`, а про high-throughput нагрузку на очереди, worker-процессы и dispatch-пайплайны.
- Что делал: сопровождал инфраструктуру batch/dispatch-контуров, участвовал в эксплуатации сервисов с большими очередями, контроле backlog, retries, rate limits, observability и устойчивости фоновых процессов доставки.
- Что можно безопасно заявлять публично: очереди доходили до `10 млн` сообщений, а основной эксплуатационный фокус был в надёжности асинхронной обработки, масштабировании worker-слоя и разборе узких мест.
- Что это доказывает: опыт не только в обычном `CI/CD + Kubernetes`, но и в эксплуатации high-throughput систем, где критичны очереди, фоновая обработка, stateful-компоненты, мониторинг и предсказуемость доставки.
- Результат: повышение устойчивости массовых рассылок, уменьшение ручного вмешательства в delivery-процессы и лучшая наблюдаемость проблем в очередях и фоновых задачах.

## 3. Контур доставки Telegram-ботов

- Контекст: отдельные Telegram-боты и связанные API/worker-сервисы, которые нужно было выкатывать как управляемые Kubernetes-приложения в нескольких окружениях.
- Что делал: работал с `Helm` values для отдельных bot-сервисов, GitOps-структурой кластеров, `ArgoCD ApplicationSet`, доставкой секретов через `Vault`, `ExternalDNS` для доменов и `Istio Gateway` / `VirtualService` для входного трафика.
- Что это доказывает: опыт не только в эксплуатации Telegram-контуров, но и в их нормальной production-упаковке: конфигурация по окружениям, секьюрная доставка секретов, routing, DNS и воспроизводимый deploy.
- Почему это важно: такой кейс хорошо ложится на роли, где нужно делать Telegram-ботов и интеграции не как "скрипт на коленке", а как сервис с понятным deployment-процессом.

## 3a. Личный VPN с Telegram-администрированием

- Контекст: небольшой VPS-контур для личного использования и нескольких родственников, где сайт, nginx и VPN уже совместно используют хост.
- Что сделано: разделён WebSocket-маршрут VPN через nginx, внутренний порт Xray привязан к localhost, конфигурация вынесена в постоянное хранилище, добавлены log rotation, backup/валидация и диагностика сервисов.
- Управление: Python-бот с русским интерфейсом, long polling, SQLite, allowlist администраторов, одноразовыми семейными приглашениями, заявками, выдачей/отзывом доступа и audit trail. Профиль бессрочный по умолчанию, но может быть отозван владельцем.
- UX и надёжность: для Happ профиль выдаётся QR-кодом, сформированным в памяти, и резервной ссылкой; для AmneziaVPN — текстовым ключом. После инцидентов выдачи были разделены проверка helper, права `systemd`, запись SQLite и health check, чтобы не сообщать об успехе до фактической готовности профиля.
- Безопасность: бот не имеет Docker/root-доступа; привилегированные операции выполняет отдельный allowlisted helper. В публичном артефакте исключены все реальные реквизиты и профили.
- Публичный пример: [VPN Telegram Admin Bot](../artifacts/vpn-telegram-admin-bot/README.md).

## 4. Реестр и доставка образов в tgbot/tgbots

- Контекст: в Telegram-контуре нужно было поддерживать воспроизводимую доставку контейнерных образов через `Helm` и `ArgoCD`, с управлением `image repository`, тегами и доступом к registry.
- Что делал: сопровождал `ArgoCD Image Updater`, `ApplicationSet`, `image.repository` / `image.tag`, `pull secrets` и связанные build/deploy шаблоны для `tgbot/tgbots`-сервисов.
- Что подтверждается артефактами: `rnd-argocd/clusters/tgbots-dev/apps/applicationset.yaml`, `rnd-argocd/clusters/tgbots-dev/apps/applicationset-files.yaml`, `tgbots-components/templates/tgbots.yml`, `tgbots-components/CHANGELOG.md`.
- Что это доказывает: опыт не только с самим Kubernetes-деплоем, но и с реальным release-delivery слоем вокруг registry, image updater, naming conventions и секретов доступа.
- Почему это важно: в таких задачах меняется не один YAML. Обычно приходится одновременно держать в порядке CI templates, `Helm` values, GitOps-генерацию приложений и доступ к registry.

## 5. Retool, Debezium и задачи миграций в tgbot/tgbots

- Контекст: в зоне `tgbot/tgbots` помимо основного delivery-контура были adjacent-задачи вокруг `Retool`, `Debezium` и migration jobs в chart values.
- Что делал: участвовал в rollout/support `Retool` в `tgbot`-контуре; сопровождал `Debezium`-компоненты в `rnd-argocd/clusters/tgbots-dev/infra-apps`; работал с `job` / `revertJob`, где вызываются `prod:apply-migrations` и `prod:migration:revert` в `tgbot-сharts`.
- Что подтверждается путями и конфигами: `ops/terraform/tgbot/prod/ec2/retool2/`, `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-postgres/`, `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-mongo/`, `tgbot-сharts/dev/`, `tgbot-сharts/prod/`.
- Отдельный безопасный разбор по локальному архиву: [Дополнительные данные по tgbot/tgbots](./ZEROONETECH_EVIDENCE.md)
- Важное уточнение: по самим `chart values` видно наличие `apply/revert` migration flow, но эти файлы не доказывают конкретный движок БД. Поэтому корректная формулировка здесь: `миграции схемы приложения / сервисной БД`, а не жёсткое утверждение про `PostgreSQL` или `MariaDB`.
- Что это доказывает: опыт не только в стандартном `k8s + CI/CD`, но и в adjacent platform/data tooling внутри Telegram-контура: internal admin tooling, `CDC`-компоненты и контролируемые migration/revert-процессы при релизах.

## 6. Azure, AKS и подготовка к PCI DSS

- Контекст: fintech-инфраструктура в Azure.
- Что делал: IaC на `Terraform/Terragrunt`, GitOps через `FluxCD + GitLab CI`, AKS node pools, autoscaling, network policies, private ingress, Key Vault, аудитный след.
- Что это доказывает: опыт не только deployment-задач, но и platform/security-oriented DevOps работы.
- Результат: подготовка инфраструктурного контура к внешнему аудиту, ускорение релизного цикла и снижение эксплуатационных рисков.

## 7. Yandex Cloud / аналитическая платформа

- Контекст: инфраструктура аналитической платформы в Yandex Cloud.
- Что делал: сопровождение Kubernetes-кластера, CI/CD и GitOps-процессов, эксплуатация Airflow / Trino / JupyterHub / GitLab Runner, работа с Vault / External Secrets, ingress, registry и observability.
- Что это доказывает: уверенную работу в облаке, платформенных сервисах и data-инфраструктуре.
- Результат: поддержка production/dev контуров, развитие платформы и снижение ручной нагрузки на сопровождение.

## 8. Набор автоматизации резервного копирования и восстановления

- Контекст: отдельный рабочий каталог с эксплуатационными артефактами по резервному копированию, восстановлению и миграции данных.
- Подтверждающие артефакты: Python-скрипты `daily_backups_lambda.py`, `restore_backups.py`, `daily_backups_mongodb.py`, Kubernetes manifests для cron-based backup/restore задач, Dockerfiles и shell-сценарии экспорта.
- Что делал: автоматизация backup/restore контуров для PostgreSQL, MariaDB и MongoDB, интеграция с `AWS S3`, `Secrets Manager`, `Slack`-оповещением и Kubernetes CronJob.
- Что это доказывает: опыт не только в CI/CD и k8s delivery, но и в data operations, backup policy, recovery workflow и эксплуатационных сценариях вокруг stateful сервисов.
- Результат: отдельный воспроизводимый слой доказательств по backup automation, даже там, где в архиве не сохранилась читаемая git-история.
