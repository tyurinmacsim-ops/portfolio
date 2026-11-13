# Резюме

## Максим Тюрин

- Роль: `DevOps / Platform Engineer`
- Локация: `Пермь`
- Формат работы: `удалённо`; переезд и командировки не рассматриваю
- Контакты: `tyurinmacsim@gmail.com`, [Telegram `@Max_Tyurin`](https://t.me/Max_Tyurin)

## Кратко

DevOps / Platform-инженер, около 5 лет в DevOps и почти 10 лет в IT. Развиваю Kubernetes- и Linux-инфраструктуру, автоматизирую CI/CD и IaC, разбираю production-инциденты и восстанавливаю сервисы. Есть практический опыт внедрения безопасности совместно с инженером ИБ.

Полностью удалённо из Перми, без переезда. Предпочтительный рабочий язык — русский. Английский — B1, по результату теста Duolingo.

## Основной стек

- Инфраструктура: Linux, Docker, Kubernetes, EKS, AKS, AWS, Azure, Yandex Cloud, Selectel.
- Автоматизация: Terraform, Terragrunt, OpenTofu, Ansible, GitLab CI/CD, Helm, Argo CD, FluxCD, Kustomize, Crossplane, Bash, Python.
- Безопасность: Kyverno, Trivy, Wazuh, Vault, External Secrets, FreeIPA, SSH-hardening, TLS, RBAC/IAM.
- Наблюдаемость и данные: Prometheus, VictoriaMetrics, Grafana, Loki, Alertmanager, PostgreSQL, MongoDB, Redis, Kafka, RabbitMQ, ClickHouse, Restic.

## Ключевые результаты

- В 01.tech автоматизировал типовые выкладки 100+ микросервисов через GitLab CI/CD, IaC, Helm и Flux/GitOps. Выкладка вместо ручных команд на ВМ (около 1,5 часа) занимала 10–15 минут.
- По моей примерной оценке, после перехода от ручного обслуживания к IaC и автоматизированным pipeline MTTR снизился на 45–60%; IaC и pipeline сократили ручные действия при восстановлении, а централизованные метрики, логи и алерты помогали быстрее находить причину сбоя.
- Вместе с ИБ внедрял Kyverno и Trivy в Kubernetes, Wazuh-агенты на ВМ; автоматизировал SSH-hardening через Ansible.
- В PERX участвовал в аварийном восстановлении и переносе сервисов из Yandex Cloud в Selectel; поэтапно обновил Traefik на 22 ВМ.
- Устранил причину повторных Kubernetes-алертов от потерянных временных worker-нод; доработал MongoDB backup в Restic и сохранение настроек окружений при восстановлении.
- В Hilbert Team исправлял несовместимость зависимостей Airflow, ошибки CI и доступа к S3; сопровождал управление доступами к DWH через Git.

[Подробнее об опыте DevSecOps](./DEVSECOPS.md) · [DevOps на hh](https://perm.hh.ru/resume/96e16841ff03f2062d0039ed1f5968795a6d61) · [DevSecOps на hh](https://perm.hh.ru/resume/b8488b73ff115787bf0039ed1f6a4859616f78)

## Опыт

### PERX / MyNaghi | 2026-08 — 2026-10

Production и dev/stage в Yandex Cloud, AWS и Selectel; общий парк около 100 серверов. Единственный DevOps-инженер на стороне компании при поддержке лида-наставника.

- Выстроил GitLab CI для OpenTofu/Terraform: проверки, plan, контролируемый apply и поиск расхождений. Добавил Trivy-проверки IaC и Kubernetes-конфигураций с остановкой проверки при HIGH/CRITICAL.
- Участвовал в восстановлении после отказа дата-центров Yandex Cloud и переносе в Selectel. Восстанавливал PostgreSQL, MongoDB, Keycloak и внутренние сервисы из резервных копий и снапшотов; инцидент затронул около 30 ВМ с сайтами и 20 серверов внутренних сервисов.
- Автоматизировал временные worker-ноды Airflow/importer через Crossplane в Yandex Cloud и AWS. Для очистки потерянных Node добавил проверки отсутствия ВМ и активных workload pod; это устранило причину повторных алертов DaemonSet.
- Перевёл MongoDB backup на потоковую передачу дампа в Restic, ограничивал CPU, память и I/O резервного копирования. При восстановлении dev/stage сохранял настройки интеграций окружения, чтобы не заменять их production-настройками.
- Усиливал securityContext и ограничения привилегий Kubernetes workload, настраивал явный короткоживущий ServiceAccount token. Сопровождал приватный доступ GitLab Runner через NetBird и настройку серверов Ansible.
- Исправлял условия алертов Prometheus/Grafana для временных нод, Job и backup. Поэтапно обновил Traefik на 22 ВМ Selectel.
- Сопровождал self-managed Kubernetes, Helm и Argo CD, публикацию сайта MyNaghi из S3 через CloudFront и управление кэшем.

### Hilbert Team | 2025-12 — 2026-08

Проектный контракт для Magnit Tech: DWH и аналитическая платформа в Yandex Cloud. Работал единственным DevOps-инженером со стороны Hilbert Team.

- Поддерживал production/dev Airflow, Trino, JupyterHub и Kafka Connect в Kubernetes; GitOps и CI/CD через FluxCD, GitLab CI, Helm и Kustomize.
- Участвовал в подготовке перехода на Airflow 3.1: адаптировал CI стендов и управление секретами. Исправлял несовместимость Python-зависимостей, мешавшую миграциям Airflow, и развёртывание при зависшем удалении namespace.
- Управлял доступами к Greenplum, ClickHouse, Trino, JupyterHub и S3 через Git: группы, роли, сервисные учётные записи. Разбирал конфликты bucket policy и Terraform, вызывавшие ошибки 403.
- Сопровождал Vault, External Secrets, TLS, ingress и registry; убирал вывод учётных данных из CI-логов при подготовке Airflow-стендов.
- Настраивал мониторинг etcd, HTTP/gRPC, ошибок 5xx и задержек p95/p99. Уточнял временные окна алертов облачных квот, разделял WARNING/CRITICAL, добавлял ссылки на инструкции и дашборды.
- Работал с Terraform и Kubernetes, включая GPU-ресурсы; поддерживал образы Airflow с ML-зависимостями и инфраструктуру LLM/RAG-приложений.

### 01.tech | 2023-09 — 2025-11

Telegram-платформа на Node.js: более 100 микросервисов в production, AWS/EKS. В первый год был единственным DevOps-инженером проекта, затем работал в паре; взаимодействовал с разработчиками, тимлидом и инженером ИБ.

- Автоматизировал типовые выкладки через GitLab CI/CD, Helm и Flux/GitOps, развивал Terraform/Terragrunt и общие CI-шаблоны. Ручные команды на ВМ занимали около 1,5 часа, доставка через pipeline — 10–15 минут. Участвовал в миграции сервисов с EC2/Docker Compose в Kubernetes.
- По моей примерной оценке, после перехода от ручного обслуживания к IaC и автоматизированным pipeline MTTR снизился на 45–60%; IaC и pipeline сократили ручные действия при восстановлении, а централизованные метрики, логи и алерты помогали быстрее находить причину сбоя.
- Вместе с ИБ внедрял Kyverno: перевод политик из Audit в Enforce, запуск не от root, read-only root filesystem, seccomp, ограничения capabilities, привилегий, hostPath и host namespaces. Сопровождал RBAC-политики и исключения для системных компонентов.
- Внедрял Trivy Operator для проверок конфигурации и инфраструктуры Kubernetes. Доставлял настройки безопасности через GitOps, адаптировал securityContext приложений.
- Автоматизировал SSH/SecOps через Ansible: доступ по ключам, запрет входа root и паролей, интеграция с FreeIPA, проверка sshd-конфигурации перед применением. Совместно с ИБ внедрял Wazuh-агенты на ВМ и подключал хосты к мониторингу безопасности.
- Сопровождал Vault и External Secrets, TLS, DNS, Istio Gateway, ExternalDNS и обновление приложений при изменении Secret/ConfigMap.
- Поддерживал PostgreSQL/RDS, MongoDB, Redis, Kafka, RabbitMQ и ClickHouse; автоматизировал backup/restore, сопровождал migration jobs и откат миграций через Helm/Argo CD.
- Разбирал production-инциденты и работу крупных асинхронных очередей: backlog, повторную обработку, rate limiting и состояние worker-процессов. Настраивал VictoriaMetrics, Grafana, Loki и Alertmanager.
- Поддерживал инфраструктуру Retool, компоненты Debezium/CDC для PostgreSQL и MongoDB, VPN-доступ FortiGate/FortiClient.

### Azure-проект (название не раскрывается) | 2022-07 — 2023-08

Финтех-проект на Azure. Работал в команде DevOps, участвовал в подготовке инфраструктуры к требованиям PCI DSS.

- Создал повторно используемые Terraform/Terragrunt-модули, настроил удалённый state и проверки конфигурации.
- Настроил GitOps через FluxCD и GitLab CI, сборку и развёртывание Helm-чартов; работал с канареечными релизами.
- Сопровождал AKS: пулы узлов, автомасштабирование, сетевые политики, приватные ingress и Private Link к Azure PaaS.
- Описывал в Terraform Kubernetes, сети, ВМ и NSG; настраивал роли/права для Ansible, firewall, учётные записи и порты.
- Участвовал в настройке аудита, журналирования и security enforcement. Использовал GitLab SAST/DAST и рекомендованные командой средства проверки безопасности; устранял замечания из отчётов аудита.
- Поддерживал мониторинг, OpenSearch и Loki, сроки хранения логов и маскирование персональных данных. Вместе с командой оптимизировал ресурсы через автомасштабирование и очистку хранилищ.

### SWAPP Protocol | 2021-11 — 2022-06

- `AWS`, `Hetzner`, `Terraform`, `Ansible`
- `Docker`, `Kubernetes`, `Proxmox`, `Cloudflare`
- `PostgreSQL`, `MySQL`, `Redis`, `ClickHouse`

## Дополнение

- Связка с доказательствами в портфолио: [Сопоставление резюме и портфолио](./RESUME_PORTFOLIO_MAP.md)
- Публичные артефакты: [Дополнительные артефакты](./ARTIFACT_EVIDENCE.md)
