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

## 3. VPN Telegram Admin Bot

- Тип артефакта: небольшой личный контур управления VPN для владельца и ограниченной группы пользователей.
- Что показывает: `Python`, Telegram long polling, русский UI, `SQLite`, `systemd`, Xray, nginx WebSocket proxy и безопасную границу привилегий.
- Ключевой паттерн: бот не получает Docker/root-доступ. Он вызывает только allowlisted helper, который выполняет backup → validate → apply → health check для Xray.
- Доступ: одноразовое приглашение → анкета → ручное одобрение; затем один персональный бессрочный профиль с явным отзывом владельцем.
- UX: Happ получает QR-код, созданный в памяти, и резервную VLESS-ссылку; Happ Desktop на ПК — текстовый ключ и `.txt`-файл. Владелец также может вручную завести профиль родственнику без Telegram.
- Эксплуатация: раздельно проверяются права `systemd`, права helper и изменяемые каталоги Xray, чтобы ошибка доступа не превращалась в «успешную» выдачу профиля.
- Публичный sanitized bundle: [artifacts/vpn-telegram-admin-bot](../artifacts/vpn-telegram-admin-bot/README.md).
- Что не публикуется: токен бота, ID канала, домен/IP, UUID, реальные VPN-ссылки, QR-коды, логи и ключи TLS/Reality.
