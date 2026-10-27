terraform {
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "17.3.1"
    }
    helm = {
      source  = "helm"
      version = "2.14.0"
    }
    # argocd = {
    #   source = "oboukili/argocd"
    #   version = "6.1.1"
    # }
    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = "0.1.2"
    }
    age = {
      source  = "clementblaise/age"
      version = "0.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }
  }

  # backend "http" {
  #   # configured by environment
  # }
}

provider "gitlab" {
  base_url = var.gitlab_api_url
}

provider "helm" {
}

provider "bcrypt" {
}

provider "age" {
}

provider "kubernetes" {
}

provider "argocd" {
  # port_forward_with_namespace = local.argocd_namespace
  server_addr = "argocd.prod.smgl.sh:443"
  insecure    = false
  username    = local.argocd_admin_user
  password    = var.argocd_admin_password
}
