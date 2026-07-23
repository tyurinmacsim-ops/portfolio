# Публичные демо-проекты

## 1. platform-engineering-demo

- Путь: [projects/platform-engineering-demo](../projects/platform-engineering-demo/README.md)
- Что показывает: `Terraform`, `Helm`, `Kubernetes`, `GitHub Actions`, `Prometheus`, `Grafana`, `Loki`, `kind`

### Что внутри

- bootstrap `kind`-кластера;
- Terraform-установка observability-стека;
- деплой демонстрационного приложения с `/healthz`, `/readyz`, `/metrics`;
- `ServiceMonitor`, `HPA`, `PDB`;
- CI-пайплайн с validate и smoke-этапами.

### Зачем это в портфолио

- это уже не описание опыта, а рабочий воспроизводимый артефакт;
- техлид может быстро увидеть подход к platform engineering;
- репозиторий можно приложить как прямую ссылку в отклике или реферальной форме.

## 2. Контур доставки Telegram-ботов

- Тип артефакта: подтверждаемый рабочий контур по деплою Telegram-сервисов и связанных приложений.
- На чём основан: `Helm values` для bot-сервисов, `ArgoCD ApplicationSet`, `Vault` secret delivery, `ExternalDNS`, `Istio Gateway`, GitOps-структура кластеров `tgbots-dev` / `tgbots-prod`.

### Что показывает

- `Helm` и values-файлы для отдельных bot/app-инстансов;
- GitOps-доставку через `ArgoCD ApplicationSet`;
- раздельные `dev/prod` контуры;
- доставку runtime-секретов через `Vault`;
- автоматическое управление DNS через `ExternalDNS`;
- входной трафик через `Istio Gateway` / `VirtualService`;
- работу не только с одним приложением, а с fleet-подходом для большого числа сервисов.

### Какие артефакты это подтверждают

- Telegram-ориентированные values-файлы в рабочем архиве: `tgbot-чарты` / `prod/*.yaml`
- `ApplicationSet` для `tgbots-prod` и `tgbots-dev`
- infra-apps для `external-dns`, `gateways`, `vault-webhook`, `external-secrets`
- values с `Istio`-ingress и `Vault` annotations для конкретных bot/API-сервисов
- публичный sanitized bundle в репозитории: [artifacts/telegram-bot-delivery](../artifacts/telegram-bot-delivery/README.md)

### Почему это важно

- это показывает не просто "умею писать манифесты", а понимаю, как довести бот или API-интеграцию до production deployment;
- такой контур хорошо ложится на роли, где нужно собирать Telegram-ботов, интеграции и поддерживать их в рабочем состоянии;
- особенно полезно для вакансий, где ожидают не только код, но и нормальную упаковку, выкладку, конфигурацию и сопровождение.
