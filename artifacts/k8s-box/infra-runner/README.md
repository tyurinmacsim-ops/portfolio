# infra-runner (стек Terragrunt)

Создает внешнюю VM с GitLab runner, которая используется инфраструктурным конвейером.

## Обязательные переменные окружения

1. `TF_VAR_YC_TOKEN` or `YC_TOKEN`
2. `K8S_BOX_GITLAB_URL`
3. `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN`

## Команды

```bash
cd infra-runner
terragrunt init
terragrunt plan
terragrunt apply
```
