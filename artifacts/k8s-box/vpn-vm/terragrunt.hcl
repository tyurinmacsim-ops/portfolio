terraform {
  source = "../yc-vpn-vm-module"
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
    private_subnets = {
      "10.0.1.0/24" = {
        subnet_id = "e9b00000000000000000"
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan", "destroy", "output"]
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.yc_zone
}
EOF
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  deployment_env  = get_env("K8S_BOX_DEPLOYMENT_ENV", "test")
  vpn_subnet_cidr = get_env("K8S_BOX_VPN_VM_SUBNET_CIDR", get_env("K8S_BOX_SUBNET_CIDR", "10.0.1.0/24"))
  vpn_name        = get_env("K8S_BOX_VPN_VM_NAME", "vpn-vm")
  vpn_platform_id = get_env("K8S_BOX_VPN_VM_PLATFORM_ID", "standard-v3")

  vpn_cores             = tonumber(get_env("K8S_BOX_VPN_VM_CORES", "2"))
  vpn_memory_gb         = tonumber(get_env("K8S_BOX_VPN_VM_MEMORY_GB", "2"))
  vpn_core_fraction     = tonumber(get_env("K8S_BOX_VPN_VM_CORE_FRACTION", "50"))
  vpn_boot_disk_size_gb = tonumber(get_env("K8S_BOX_VPN_VM_BOOT_DISK_GB", "30"))

  vpn_boot_image_family        = get_env("K8S_BOX_VPN_VM_IMAGE_FAMILY", "ubuntu-2204-lts")
  vpn_admin_cidr_blocks        = compact(split(",", get_env("K8S_BOX_VPN_VM_ADMIN_CIDRS", "0.0.0.0/0")))
  vpn_enable_openvpn           = lower(get_env("K8S_BOX_VPN_VM_ENABLE_OPENVPN", "false")) == "true"
  vpn_openvpn_port             = tonumber(get_env("K8S_BOX_VPN_VM_OPENVPN_PORT", "1194"))
  vpn_enable_wireguard         = lower(get_env("K8S_BOX_VPN_VM_ENABLE_WIREGUARD", "true")) == "true"
  vpn_enable_oslogin           = lower(get_env("K8S_BOX_VPN_VM_ENABLE_OSLOGIN", "false")) == "true"
  vpn_ssh_username             = get_env("K8S_BOX_VPN_VM_SSH_USERNAME", "ubuntu")
  vpn_ssh_public_key           = trimspace(try(file(pathexpand(get_env("K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH", "~/.ssh/id_ed25519.pub"))), ""))
  vpn_wireguard_port           = tonumber(get_env("K8S_BOX_VPN_VM_WIREGUARD_PORT", "51820"))
  vpn_wireguard_network_cidr   = get_env("K8S_BOX_VPN_VM_WIREGUARD_NETWORK_CIDR", "10.250.0.0/24")
  vpn_wireguard_server_address = get_env("K8S_BOX_VPN_VM_WIREGUARD_SERVER_ADDRESS", "10.250.0.1/24")
  vpn_wireguard_network_prefix = get_env("K8S_BOX_VPN_VM_WIREGUARD_NETWORK_PREFIX", "10.250.0")
  vpn_wireguard_client_dns     = get_env("K8S_BOX_VPN_VM_WIREGUARD_CLIENT_DNS", "1.1.1.1,8.8.8.8")
  vpn_wireguard_allowed_ips    = get_env("K8S_BOX_VPN_VM_WIREGUARD_ALLOWED_IPS", "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16")
  vpn_create_service_account   = lower(get_env("K8S_BOX_VPN_VM_CREATE_SERVICE_ACCOUNT", "true")) == "true"
  vpn_service_account_name     = get_env("K8S_BOX_VPN_VM_SERVICE_ACCOUNT_NAME", "vpn-vm-sa")
}

inputs = {
  cloud_id   = local.env_vars.locals.cloud_id
  folder_id  = dependency.folder.outputs.folder_id
  yc_zone    = local.env_vars.locals.yc_zone
  network_id = dependency.vpc.outputs.vpc_id
  subnet_id  = try(dependency.vpc.outputs.private_subnets[local.vpn_subnet_cidr].subnet_id, values(dependency.vpc.outputs.private_subnets)[0].subnet_id)

  name              = local.vpn_name
  platform_id       = local.vpn_platform_id
  cores             = local.vpn_cores
  memory            = local.vpn_memory_gb
  core_fraction     = local.vpn_core_fraction
  boot_disk_size    = local.vpn_boot_disk_size_gb
  boot_image_family = local.vpn_boot_image_family
  nat               = true

  admin_cidr_blocks = local.vpn_admin_cidr_blocks
  enable_openvpn    = local.vpn_enable_openvpn
  openvpn_port      = local.vpn_openvpn_port
  enable_wireguard  = local.vpn_enable_wireguard
  wireguard_port    = local.vpn_wireguard_port

  create_service_account = local.vpn_create_service_account
  service_account_name   = local.vpn_service_account_name
  service_account_roles  = ["editor"]
  enable_oslogin         = local.vpn_enable_oslogin
  ssh_username           = local.vpn_ssh_username
  ssh_public_key         = local.vpn_ssh_public_key

  user_data = templatefile("${get_terragrunt_dir()}/../vpn/cloud-init-vpn-vm.yaml.tpl", {
    hostname                 = local.vpn_name
    ssh_public_key           = local.vpn_enable_oslogin ? "" : local.vpn_ssh_public_key
    wireguard_port           = local.vpn_wireguard_port
    wireguard_network_cidr   = local.vpn_wireguard_network_cidr
    wireguard_server_address = local.vpn_wireguard_server_address
    wireguard_network_prefix = local.vpn_wireguard_network_prefix
    wireguard_client_dns     = local.vpn_wireguard_client_dns
    wireguard_allowed_ips    = local.vpn_wireguard_allowed_ips
  })

  labels = {
    environment = local.deployment_env
    managed_by  = "terraform"
    role        = "vpn-vm"
  }
}
