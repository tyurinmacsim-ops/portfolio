locals {
  cloud_id     = "b1goatn43hbd65t80qcn"
  yc_zone      = "ru-central1-a"
  network_name = "k8s-vpc-01"
  folder_name  = "internal-k8s-box"
  # yc_token должен быть задан через переменную окружения TF_VAR_yc_token
}
