# Terraform-модуль `yc-k8s-module`

## Назначение
Создание managed Kubernetes-кластера в Yandex Cloud и групп нод.

## Основные ресурсы
- `yandex_kubernetes_cluster`
- `yandex_kubernetes_node_group`
- IAM-ресурсы для control plane и worker nodes

## Ключевые переменные
- Координаты: `cloud_id`, `folder_id`, `yc_token`
- Сеть: `network_id`, `master_locations`, диапазоны pod/service
- Кластер: `name`, `cluster_version` / `master_version`, `public_access`
- Ноды: `node_groups`
- Безопасность: `master_security_group_ids`, `node_groups_default_security_groups_ids`
- Надежность создания: `cluster_create_iam_delay_seconds` для паузы после IAM bindings и перед `CreateCluster`

## IAM-правила, которые модуль выдает автоматически
- Service account control plane получает:
  - `k8s.clusters.agent` для обычного Calico-кластера;
  - `k8s.tunnelClusters.agent` для tunnel/Cilium-режима;
  - `vpc.publicAdmin`, если у мастера или node group есть public IP;
  - `load-balancer.admin`, если разрешены public LoadBalancer-сервисы;
  - `vpc.privateAdmin`, `vpc.user`, `vpc.bridgeAdmin` для cross-folder VPC;
  - дополнительно `vpc.publicAdmin` в VPC-folder, если cross-folder сеть используется вместе с public IP.
- Node service account получает:
  - `container-registry.images.puller`.

Это важно: `public master` и `public load balancers` — разные сценарии. Для public master нужен `vpc.publicAdmin` даже если `allow_public_load_balancers=false`.

## Outputs (основные)
- `cluster_id`
- `cluster_name`
- `external_v4_endpoint`
- `cluster_ca_certificate`

## Где используется
- Terragrunt-слой: `k8s-box/test-cluster-k8s/terragrunt.hcl`.
