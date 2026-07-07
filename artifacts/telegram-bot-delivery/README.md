# Telegram Bot Delivery Bundle

Публичный sanitized-набор артефактов для портфолио: пример Telegram-бота на `Python` и рядом типовой deployment-контур, который показывает, как такой сервис упаковывается и выкатывается в Kubernetes.

Что важно:

- это не "учебный hello world", а публичный sample, собранный по мотивам рабочих deployment-паттернов;
- реальные домены, registry paths, secret paths, chat ids, webhook URL и внутренние имена убраны;
- логика сохранена: бот как сервис, контейнеризация, values по окружениям, GitOps, секреты через Vault, DNS и gateway-слой.

## Что внутри

- [app/main.py](app/main.py) — минимальный async Telegram-бот с webhook и mock CRM integration
- [app/config.py](app/config.py) — конфигурация через env
- [app/requirements.txt](app/requirements.txt)
- [app/Dockerfile](app/Dockerfile)
- [PROMPTS.md](PROMPTS.md) — пример prompt-файла под LLM-assisted workflow
- [deploy/argocd/applicationset.yaml](deploy/argocd/applicationset.yaml)
- [deploy/helm-values/dev/lead-qualifier-bot.yaml](deploy/helm-values/dev/lead-qualifier-bot.yaml)
- [deploy/helm-values/prod/lead-qualifier-bot.yaml](deploy/helm-values/prod/lead-qualifier-bot.yaml)
- [deploy/infra/external-dns.application.yaml](deploy/infra/external-dns.application.yaml)
- [deploy/infra/istio-gateway.applicationset.yaml](deploy/infra/istio-gateway.applicationset.yaml)
- [deploy/infra/vault-secrets-webhook.values.yaml](deploy/infra/vault-secrets-webhook.values.yaml)

## Что это подтверждает

- `Python` и async-подход для Telegram-ботов;
- работу с `HTTP API` и webhook-моделью;
- контейнеризацию и вынесение конфигурации из кода;
- `Helm` values по окружениям;
- GitOps-доставку через `ArgoCD ApplicationSet`;
- секреты через `Vault`;
- домены через `ExternalDNS`;
- входной трафик через `Istio Gateway`.

## Как об этом говорить на собеседовании

Если коротко:

`Я могу собрать Telegram-бота как обычный production-сервис: код на Python, контейнер, env-конфигурация, values по окружениям, секреты вне Git, GitOps-деплой и сетевой вход через gateway.`
