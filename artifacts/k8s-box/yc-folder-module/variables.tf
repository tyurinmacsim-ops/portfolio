variable "folders" {
  description = "Map of folders to create"
  type = map(object({
    cloud_id           = string
    folder_name        = string
    folder_description = string
  }))
}

# Переменная для провайдера
variable "cloud_id" {
  description = "The ID of the cloud"
  type        = string
}

# Токен для аутентификации в Yandex Cloud
variable "yc_token" {
  description = "OAuth token for Yandex Cloud"
  type        = string
  default     = null
}
