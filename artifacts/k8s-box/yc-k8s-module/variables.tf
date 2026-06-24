#
# yandex cloud coordinates
#
variable "yc_token" {
  type        = string
  description = "OAuth token for Yandex Cloud"
}

variable "folder_id" {
  description = "The ID of the folder that the Kubernetes cluster belongs to."
  type        = string
  default     = null
}

variable "cloud_id" {
  description = "The ID of the cloud that the Kubernetes cluster belongs to."
  type        = string
}

variable "main_folder_id" {
  description = "The ID of the main folder with VPC."
  type        = string
  default     = ""
}
#
# naming
#
variable "name" {
  description = "K8S cluster name"
  type        = string
}

variable "description" {
  description = "K8S cluster description"
  type        = string
  default     = ""
}

variable "labels" {
  description = "A set of labels to assign to the K8S cluster"
  type        = map(string)
  default     = {}
}


variable "cluster_name" {
  description = "Name of a specific Kubernetes cluster."
  type        = string
  default     = "k8s-cluster"
}


#
# K8S сluster network
#
variable "network_id" {
  description = "The ID of the cluster network"
  type        = string
  default     = null
}



variable "cluster_ipv4_range" {
  description = <<-EOF
  CIDR block. IP range for allocating pod addresses. It should not overlap with
  any subnet in the network the K8S cluster located in. Static routes will
  be set up for this CIDR blocks in node subnets
  EOF
  type        = string
  default     = null
}

variable "cluster_ipv6_range" {
  description = "Identical to cluster_ipv4_range but for IPv6 protocol"
  type        = string
  default     = null
}

variable "node_ipv4_cidr_mask_size" {
  description = <<-EOF
  Size of the masks that are assigned to each node in the cluster. Effectively
  limits maximum number of pods for each node
  EOF
  type        = number
  default     = null
}

variable "service_ipv4_range" {
  description = <<-EOF
  CIDR block. IP range K8S service K8S cluster IP addresses
  will be allocated from. It should not overlap with any subnet in the network
  the K8S cluster located in
  EOF
  type        = string
  default     = null
}

variable "service_ipv6_range" {
  description = "Identical to service_ipv4_range but for IPv6 protocol"
  type        = string
  default     = null
}

variable "cni_type" {
  description = "Type of K8S CNI which will be used for the cluster"
  type        = string
  default     = "calico"
}

#
# Cluster IAM
#

variable "service_account_name" {
  description = "IAM service account name."
  type        = string
  default     = "k8s-service-account"
}

variable "node_account_name" {
  description = "IAM node account name."
  type        = string
  default     = "k8s-node-account"
}

variable "service_account_id" {
  description = <<-EOF
  ID of existing service account to be used for provisioning Compute Cloud
  and VPC resources for K8S cluster. Selected service account should have
  edit role on the folder where the K8S cluster will be located and on the
  folder where selected network resides
  EOF
  type        = string
  default     = null
}

variable "use_existing_sa" {
  description = <<EOF
    Use existing service accounts for control plane and worker nodes or not.
    If `true` parameters `master_service_account_id` and `node_service_account_id` must be set.
  EOF
  type        = bool
  default     = false
}

variable "master_service_account_id" {
  description = "Existing service account ID for control plane."
  type        = string
  default     = null
}

variable "node_service_account_id" {
  description = <<-EOF
  ID of service account to be used by the worker nodes of the K8S
  cluster to access Container Registry or to push node logs and metrics.

  If omitted or equal to `service_account_id`, service account will be used
  as node service account.
  EOF
  type        = string
  default     = null
}

#
# Cluster options
#
variable "release_channel" {
  description = "K8S cluster release channel"
  type        = string
  default     = "STABLE"
}

variable "kms_provider_key_id" {
  description = "K8S cluster KMS key ID"
  type        = string
  default     = null
}

#
# Master options
#
variable "master_version" {
  description = "Version of K8S that will be used for master"
  type        = string
  default     = "1.33"
}

variable "master_public_ip" {
  description = "Boolean flag. When true, K8S master will have visible ipv4 address"
  type        = bool
  default     = true
}

variable "enable_cilium_policy" {
  description = "Flag for enabling or disabling Cilium CNI."
  type        = bool
  default     = false
}

variable "master_security_group_ids" {
  description = "List of security group IDs to which the K8S cluster belongs"
  type        = set(string)
  default     = null
}

variable "master_region" {
  description = <<-EOF
  Name of region where cluster will be created. Required for regional cluster,
  not used for zonal cluster
  EOF
  type        = string
  default     = null
}

variable "master_locations" {
  description = <<-EOF
  List of locations where cluster will be created. If list contains only one
  location, will be created zonal cluster, if more than one -- regional
  EOF
  type = list(object({
    subnet_id = string
    zone      = string
  }))
}

# Kubernetes Master node common parameters
variable "public_access" {
  description = "Public or private Kubernetes cluster"
  type        = bool
  default     = true
}

variable "allow_public_load_balancers" {
  description = "Flag for creating new IAM role with a load-balancer.admin access."
  type        = bool
  default     = true
}

variable "cluster_create_iam_delay_seconds" {
  description = "Pause after creating IAM bindings and before Kubernetes cluster creation to avoid YC IAM propagation race conditions."
  type        = number
  default     = 30
}

variable "master_auto_upgrade" {
  description = "Boolean flag that specifies if master can be upgraded automatically"
  type        = bool
  default     = false
}

variable "master_maintenance_windows" {
  description = <<EOF
  List of structures that specifies maintenance windows,
  when auto update for master is allowed

  E.g:
  ```
  master_maintenance_windows = [
    {
      start_time = "10:00"
      duration   = "5h"
    }
  ]
  ```
  EOF
  type        = list(map(string))
  default = [
    {
      start_time = "23:00"
      duration   = "3h"
    }
  ]
}


variable "master_logging" {
  description = "Master logging"
  type = object({
    enabled                    = bool
    create_log_group           = optional(bool, true)
    log_group_retention_period = optional(string, "168h")
    log_group_id               = optional(string, "")
    audit_enabled              = optional(bool, true)
    kube_apiserver_enabled     = optional(bool, true)
    cluster_autoscaler_enabled = optional(bool, true)
    events_enabled             = optional(bool, true)
  })
  default = {
    enabled = false
  }
}

#
# Cluster node groups
#
variable "node_name_prefix" {
  description = "The prefix for node group name"
  type        = string
  default     = ""
}
variable "node_groups" {
  description = "K8S node groups"
  type = map(object({
    description               = optional(string, null)
    labels                    = optional(map(string), null)
    version                   = optional(string, null)
    metadata                  = optional(map(string), {})
    platform_id               = optional(string, null)
    memory                    = optional(string, 2)
    cores                     = optional(string, 2)
    core_fraction             = optional(string, 100)
    gpus                      = optional(string, null)
    boot_disk_type            = optional(string, "network-hdd")
    boot_disk_size            = optional(string, 100)
    preemptible               = optional(bool, false)
    placement_group_id        = optional(string, null)
    nat                       = optional(bool, false)
    security_group_ids        = optional(list(string))
    network_acceleration_type = optional(string, "standard")
    container_runtime_type    = optional(string, "containerd")
    fixed_scale               = optional(map(string), null)
    auto_scale                = optional(map(string), null)
    auto_repair               = optional(bool, true)
    auto_upgrade              = optional(bool, true)
    maintenance_windows       = optional(list(any))
    node_labels               = optional(map(string), null)
    node_taints               = optional(list(string), null)
    allowed_unsafe_sysctls    = optional(list(string), [])
    max_expansion             = optional(string, null)
    max_unavailable           = optional(string, null)
    zones                     = optional(list(string), null)
    subnet_ids                = optional(list(string), null)
    node_locations = optional(list(object({
      zone      = string
      subnet_id = string
    })), [])
  }))
  default = {}
}

variable "node_groups_defaults" {
  description = "Map of common default values for Node groups."
  type        = map(any)
  default = {
    platform_id   = "standard-v3"
    node_cores    = 4
    node_memory   = 8
    node_gpus     = 0
    core_fraction = 100
    disk_type     = "network-ssd"
    disk_size     = 64
    preemptible   = false
    nat           = false
    ipv4          = true
    ipv6          = false
  }
}

variable "generate_default_ssh_key" {
  description = "If true, SSH key for node groups will be generated"
  type        = bool
  default     = true
}

variable "nodes_default_ssh_user" {
  description = "Default SSH user for node groups. Used only if generate_default_ssh_key == true"
  type        = string
  default     = "ubuntu"
}

variable "node_groups_ssh_keys" {
  description = <<-EOF
  Map containing SSH keys to install on all K8S node servers by default
  EOF
  type        = map(list(string))
  default     = {}
}

variable "node_groups_locations" {
  description = "Locations of K8S node groups. If omitted, master_locations will be used"
  type = list(object({
    subnet_id = string
    zone      = string
  }))
  default = null
}

variable "node_groups_default_security_groups_ids" {
  description = "A list of default IDs for node groups. Will be used if node_groups[<group>].security_group_ids is empty"
  type        = list(string)
  default     = []
}

variable "enable_oslogin" {
  description = "Enable OS Login for node groups"
  type        = bool
  default     = false
}

# Security group
variable "enable_default_rules" {
  description = <<-EOF
    Manages creation of default security rules.

    Default security rules:
     - Allow all incoming traffic from any protocol.
     - Allows master-to-node and node-to-node communication inside a security group.
     - Allows pod-to-pod and service-to-service communication.
     - Allows debugging ICMP packets from internal subnets.
     - Allow access to Kubernetes API via port 6443 from the subnet.
     - Allow access to Kubernetes API via port 443 from the subnet.
  EOF
  type        = bool
  default     = true
}

variable "custom_ingress_rules" {
  description = <<-EOF
    Map definition of custom security ingress rules.
    Example:
    custom_ingress_rules = {
      "rule1" = {
        protocol       = "ANY"
        description    = "rule-1"
        v4_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
        from_port      = 8090
        to_port        = 8099
      }
    }
  EOF
  type        = any
  default     = {}
}

variable "custom_egress_rules" {
  description = <<-EOF
    Map definition of custom security egress rules.
    Example:
    custom_egress_rules = {
      "rule1" = {
        protocol       = "ANY"
        description    = "rule-1"
        v4_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
        from_port      = 8090
        to_port        = 8099
      }
    }
  EOF
  type        = any
  default     = {}
}

variable "allowed_ips" {
  description = "List of allowed IPv4 CIDR blocks."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ips_ssh" {
  description = "List of allowed IPv4 CIDR blocks for an access via SSH."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_node_ssh_access" {
  description = <<-EOF
    Enables creation of node ssh access rule.

    ingress {
      protocol       = "TCP"
      description    = "Allow access to worker nodes via SSH from IP's."
      v4_cidr_blocks = var.allowed_ips_ssh
      port           = 22
    }
  EOF
  type        = bool
  default     = true
}

variable "enable_node_ports_rules" {
  description = <<-EOF
    Enables creation of NodePort port range rule.

    "rule-1" = {
      protocol       = "TCP"
      description    = "Rule allows incoming traffic from the Internet to the NodePort port range. Add ports or change existing ones to the required ports."
      v4_cidr_blocks = ["0.0.0.0/0"]
      from_port      = 30000
      to_port        = 32767
    }
  EOF
  type        = bool
  default     = true
}

variable "enable_outgoing_traffic" {
  description = "Enables all outgoing traffic. Nodes can connect to Yandex Container Registry, Yandex Object Storage, Docker Hub, and so on."
  type        = bool
  default     = true
}

variable "enable_oslogin_or_ssh_keys" {
  description = "Enabling OS Login or adding ssh-keys to metadata of node-groups."
  type        = map(any)
  default = {
    enable-oslogin = "false"
    ssh-keys       = null
  }
  validation {
    condition     = contains(["true", "false"], var.enable_oslogin_or_ssh_keys.enable-oslogin) && ((var.enable_oslogin_or_ssh_keys.enable-oslogin == "true" && var.enable_oslogin_or_ssh_keys.ssh-keys == null) || (var.enable_oslogin_or_ssh_keys.enable-oslogin == "false"))
    error_message = "Either OS Login or ssh-keys should be enabled or none of them."
  }
}

variable "custom_metadata" {
  description = "Adding custom metadata to node-groups."
  type        = map(any)
  default     = {}
}

variable "kms_key_name" {
  type    = string
  default = ""
}

variable "network_acceleration_type" {
  description = "Network acceleration type for the Kubernetes node group"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "software_accelerated"], var.network_acceleration_type)
    error_message = "network_acceleration_type must be 'standard' or 'software_accelerated'"
  }
}

variable "container_runtime_type" {
  description = "Kubernetes Node Group container runtime type"
  type        = string
  default     = "containerd"
  validation {
    condition     = contains(["containerd", "docker"], var.container_runtime_type)
    error_message = "container_runtime_type must be 'containerd' or 'docker'"
  }
}
