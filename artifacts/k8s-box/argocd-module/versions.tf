terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.80.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0, < 3.0.0"
    }

    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = " >= 0.1.2"
    }
    age = {
      source  = "clementblaise/age"
      version = ">= 0.1.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.31.0"
    }

  }
}
