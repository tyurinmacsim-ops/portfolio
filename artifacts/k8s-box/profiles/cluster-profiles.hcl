locals {
  profiles = {
    test = {
      environment                 = "test"
      cluster_version             = "1.33"
      release_channel             = "STABLE"
      cni_type                    = "calico"
      enable_cilium_policy        = false
      public_access               = true
      allow_public_load_balancers = false
      enable_nlb_hc_rule          = false
      master_auto_upgrade         = false
      master_maintenance = {
        day        = "monday"
        start_time = "03:00"
        duration   = "1h"
      }
      cluster_ipv4_range = "172.19.0.0/16"
      service_ipv4_range = "172.20.0.0/16"
      node = {
        platform_id   = "standard-v3"
        cores         = 2
        memory_gb     = 4
        core_fraction = 50
        boot_disk_gb  = 30
        preemptible   = false
      }
      worker = {
        min             = 1
        max             = 2
        initial         = 1
        max_expansion   = 1
        max_unavailable = 1
      }
      monitoring = {
        enabled         = false
        min             = 0
        max             = 0
        initial         = 0
        max_expansion   = 1
        max_unavailable = 1
      }
    }

    dev = {
      environment                 = "dev"
      cluster_version             = "1.33"
      release_channel             = "STABLE"
      cni_type                    = "calico"
      enable_cilium_policy        = false
      public_access               = true
      allow_public_load_balancers = true
      enable_nlb_hc_rule          = true
      master_auto_upgrade         = false
      master_maintenance = {
        day        = "sunday"
        start_time = "02:00"
        duration   = "2h"
      }
      cluster_ipv4_range = "172.19.0.0/16"
      service_ipv4_range = "172.20.0.0/16"
      node = {
        platform_id   = "standard-v3"
        cores         = 2
        memory_gb     = 8
        core_fraction = 100
        boot_disk_gb  = 50
        preemptible   = false
      }
      worker = {
        min             = 1
        max             = 4
        initial         = 2
        max_expansion   = 1
        max_unavailable = 1
      }
      monitoring = {
        enabled         = true
        min             = 1
        max             = 2
        initial         = 1
        max_expansion   = 1
        max_unavailable = 1
      }
    }

    prod = {
      environment                 = "prod"
      cluster_version             = "1.33"
      release_channel             = "STABLE"
      cni_type                    = "calico"
      enable_cilium_policy        = false
      public_access               = false
      allow_public_load_balancers = true
      enable_nlb_hc_rule          = true
      master_auto_upgrade         = true
      master_maintenance = {
        day        = "sunday"
        start_time = "01:00"
        duration   = "3h"
      }
      cluster_ipv4_range = "172.19.0.0/16"
      service_ipv4_range = "172.20.0.0/16"
      node = {
        platform_id   = "standard-v3"
        cores         = 4
        memory_gb     = 16
        core_fraction = 100
        boot_disk_gb  = 64
        preemptible   = false
      }
      worker = {
        min             = 3
        max             = 12
        initial         = 3
        max_expansion   = 2
        max_unavailable = 1
      }
      monitoring = {
        enabled         = true
        min             = 1
        max             = 3
        initial         = 1
        max_expansion   = 1
        max_unavailable = 1
      }
    }
  }
}
