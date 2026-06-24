terraform {
  source = "../yc-security-group-module"
}

dependency "folder" {
  config_path = "../folder"
  mock_outputs = {
    folder_id = "b1g00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id = "enp00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF_PROVIDER
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
EOF_PROVIDER
}

locals {
  env_vars             = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  profiles_conf        = read_terragrunt_config("${get_terragrunt_dir()}/../profiles/cluster-profiles.hcl")
  cluster_profile_name = get_env("K8S_BOX_CLUSTER_PROFILE", "test")
  cluster_profile      = lookup(local.profiles_conf.locals.profiles, local.cluster_profile_name, local.profiles_conf.locals.profiles["test"])

  sg_name          = get_env("K8S_BOX_SECURITY_GROUP_NAME", "k8s-cluster-sg")
  sg_description   = get_env("K8S_BOX_SECURITY_GROUP_DESCRIPTION", "Security group for Kubernetes cluster nodes")
  subnet_cidr      = get_env("K8S_BOX_SUBNET_CIDR", "10.0.1.0/24")
  cluster_pod_cidr = get_env("K8S_BOX_CLUSTER_IPV4_RANGE", "172.19.0.0/16")
  service_cidr     = get_env("K8S_BOX_SERVICE_IPV4_RANGE", "172.20.0.0/16")

  api_allowed_cidrs = compact(split(",", get_env("K8S_BOX_API_ALLOWED_CIDRS", "0.0.0.0/0")))
  ssh_allowed_cidrs = compact(split(",", get_env("K8S_BOX_SSH_ALLOWED_CIDRS", local.subnet_cidr)))

  enable_icmp_rule     = lower(get_env("K8S_BOX_ENABLE_ICMP_RULE", "true")) == "true"
  enable_nodeport_rule = lower(get_env("K8S_BOX_ENABLE_NODEPORT_RULE", "false")) == "true"
  enable_nlb_hc_rule   = lower(get_env("K8S_BOX_ENABLE_NLB_HC_RULE", tostring(local.cluster_profile.enable_nlb_hc_rule))) == "true"

  nodeport_from  = tonumber(get_env("K8S_BOX_NODEPORT_FROM", "30000"))
  nodeport_to    = tonumber(get_env("K8S_BOX_NODEPORT_TO", "32767"))
  nodeport_cidrs = compact(split(",", get_env("K8S_BOX_NODEPORT_ALLOWED_CIDRS", "0.0.0.0/0")))

  ingress_rules_with_cidrs = concat(
    [
      {
        description    = "K8s pod/service intra-cluster traffic"
        protocol       = "ANY"
        from_port      = 0
        to_port        = 65535
        v4_cidr_blocks = [local.cluster_pod_cidr, local.service_cidr]
      },
      {
        description    = "SSH access"
        protocol       = "TCP"
        port           = 22
        v4_cidr_blocks = local.ssh_allowed_cidrs
      },
      {
        description    = "Kubernetes API server"
        protocol       = "TCP"
        port           = 443
        v4_cidr_blocks = local.api_allowed_cidrs
      }
    ],
    local.enable_icmp_rule ? [
      {
        description    = "ICMP for diagnostics"
        protocol       = "ICMP"
        from_port      = -1
        to_port        = -1
        v4_cidr_blocks = local.ssh_allowed_cidrs
      }
    ] : [],
    local.enable_nodeport_rule ? [
      {
        description    = "NodePort services"
        protocol       = "TCP"
        from_port      = local.nodeport_from
        to_port        = local.nodeport_to
        v4_cidr_blocks = local.nodeport_cidrs
      }
    ] : []
  )
}

inputs = {
  network_id = dependency.vpc.outputs.vpc_id
  folder_id  = dependency.folder.outputs.folder_id
  cloud_id   = local.env_vars.locals.cloud_id

  name        = local.sg_name
  description = local.sg_description

  self   = true
  nlb_hc = local.enable_nlb_hc_rule

  ingress_rules_with_cidrs = local.ingress_rules_with_cidrs

  egress_rules = [
    {
      description    = "All outbound traffic"
      protocol       = "ANY"
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}
