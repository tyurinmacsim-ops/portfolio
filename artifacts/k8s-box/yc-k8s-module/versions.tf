terraform {
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.80.0"
    }
  }
}
