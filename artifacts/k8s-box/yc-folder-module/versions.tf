terraform {
  required_version = ">= 1.0.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.189.0" # Последняя стабильная версия провайдера
    }
  }
}