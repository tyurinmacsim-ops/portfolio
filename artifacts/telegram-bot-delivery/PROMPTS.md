# PROMPTS.md

Этот файл показывает, как можно фиксировать рабочие промпты для LLM-assisted разработки внутри проекта.

## Prompt 1. Скелет Telegram-бота

Сгенерируй минимальный `Python`-сервис для Telegram-бота:

- async webhook-based flow
- `/start` и fallback handler
- интеграция с внешним CRM API через `aiohttp`
- health endpoint для Kubernetes
- конфигурация только через env
- логи в stdout

## Prompt 2. Deployment review

Проверь deployment-конфигурацию Telegram-бота и обрати внимание на:

- секреты не должны лежать в Git
- values должны быть разделены по окружениям
- webhook host должен приходить из конфигурации
- probes, resources и securityContext должны быть заданы явно
- deployment должен быть пригоден для GitOps

## Prompt 3. README/update

Обнови README так, чтобы было понятно:

- как запустить локально
- какие env нужны
- как работает webhook
- как бот связан с CRM
- как устроен deploy-контур
