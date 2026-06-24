# yc-runner-module

Terraform-модуль, который поднимает внешнюю VM с GitLab infra-runner в Yandex Cloud.

## Что создает

1. Опциональный сервисный аккаунт для runner VM.
2. Опциональные IAM-привязки ролей каталога для этого сервисного аккаунта.
3. `yandex_compute_instance` with cloud-init `user-data`.

## Примечания

1. Runner VM внешняя относительно Kubernetes и предназначена для выполнения инфраструктурных CI-задач.
2. Для запуска с нуля сначала поднимай runner, затем запускай CI-конвейер на этом runner.
