# Кейсы и результаты

## 1. Production GitOps / Kubernetes для multi-service продукта

- Контекст: продуктовый контур с `100+` микросервисами в production.
- Подтверждающие артефакты: коммиты в workstream'ах `GitOps / FluxCD`, `ops`, `Helm releases`, `CI templates`.
- Что делал: сопровождение AWS-инфраструктуры, перенос части сервисов в Kubernetes, настройка GitLab CI/CD, GitOps, деплой-пайплайнов, мониторинга, логирования и сервисных интеграций.
- Что это доказывает: реальную работу с `Kubernetes`, `Helm`, `FluxCD`, `Ansible`, `Terraform`, `GitLab CI`, эксплуатацией сервисов и production-процессами.
- Результат: ускорение релизов, уменьшение ручных операций, повышение частоты выкладок и снижение MTTR.

## 2. Azure / AKS / PCI DSS readiness

- Контекст: fintech-инфраструктура в Azure.
- Что делал: IaC на `Terraform/Terragrunt`, GitOps через `FluxCD + GitLab CI`, AKS node pools, autoscaling, network policies, private ingress, KMS / KeyVault, аудитный след.
- Что это доказывает: опыт не только “деплой-инженера”, но и platform/security-minded DevOps.
- Результат: ускорение релизного цикла, подготовка инфраструктурного контура к внешнему аудиту и снижение эксплуатационных рисков.

## 3. Yandex Cloud / аналитическая платформа

- Контекст: инфраструктура аналитической платформы в Yandex Cloud.
- Что делал: сопровождение Kubernetes-кластера, CI/CD и GitOps-процессов, эксплуатация Airflow / Trino / JupyterHub / GitLab Runner, работа с Vault / External Secrets, ingress, registry и observability.
- Что это доказывает: уверенную работу в облаке, платформенных сервисах и data-инфраструктуре.
- Результат: поддержка production/dev контуров, развитие платформы и снижение ручной нагрузки на сопровождение.

## 4. Что особенно важно показать на собеседовании

- Что ты умеешь работать не с одним тулом, а с целой эксплуатационной цепочкой: `cloud -> IaC -> k8s -> CI/CD -> observability -> backup/security`.
- Что у тебя есть опыт изменений в production, а не только “настроил один кластер”.
- Что ты можешь объяснить trade-offs: managed vs self-hosted, GitOps vs manual, stateful сервисы в k8s vs outside, cost vs resilience.
