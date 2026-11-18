# The foundation of a small landing zone: a project for shared services and one per tenant, their
# quotas and roles, the external network they reach the Internet and the intranet through, a
# shared security group catalogue and a DNS zone per tenant. Applied with the admin role.

terraform {
  required_version = ">= 1.9"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Admin credentials, from clouds.yaml (OS_CLOUD).
provider "openstack" {}

module "baseline" {
  source = "../.."

  baseline = {
    projects = {
      shared-services = { description = "Services shared by the tenants" }
      web             = { description = "Web tenant", quotas = { compute = { cores = 16, ram = 32768, instances = 8 }, network = { floatingip = 2, router = 2 } } }
      data            = { description = "Data tenant", quotas = { compute = { cores = 8, ram = 16384 }, volume = { gigabytes = 500 } } }
    }

    groups = {
      platform-team = { description = "Operates the shared services" }
      web-team      = { description = "Operates the web tenant" }
    }

    # Users come from the organisation's directory: adopted, never created here.
    existing = {
      users = { alice = { name = "alice" }, bob = { name = "bob" } }
    }

    role_assignments = {
      platform-member = { kind = "group", name = "platform-team", project = "shared-services", role = "member" }
      platform-lb     = { kind = "group", name = "platform-team", project = "shared-services", role = "load-balancer_member" }
      web-member      = { kind = "group", name = "web-team", project = "web", role = "member" }
      web-lb          = { kind = "group", name = "web-team", project = "web", role = "load-balancer_member" }
    }

    flavors = {
      small  = { vcpus = 2, ram = 4096, disk = 20 }
      medium = { vcpus = 4, ram = 8192, disk = 40 }
    }

    images = {
      ubuntu-24-04 = { source_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img", properties = { os_distro = "ubuntu", os_version = "24.04" } }
    }

    networks = {
      public = {
        external   = true
        share_with = ["*"]
        physnet    = "public"
        subnets = { main = {
          cidr             = "198.51.100.0/24", gateway_ip = "198.51.100.1", enable_dhcp = false
          allocation_pools = [{ start = "198.51.100.100", end = "198.51.100.199" }]
        } }
      }
      intranet = {
        external   = true
        share_with = ["shared-services", "web"]
        physnet    = "intranet"
        subnets    = { main = { cidr = "192.0.2.0/24", gateway_ip = "192.0.2.1", enable_dhcp = false } }
      }
    }

    security_groups = {
      admin-ssh = {
        description = "SSH from the administration network"
        share_with  = ["*"]
        rules       = { ssh = { direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "192.0.2.0/24" } }
      }
    }

    dns_zones = {
      web  = { name = "web.example.org.", email = "dns@example.org", project = "web" }
      data = { name = "data.example.org.", email = "dns@example.org", project = "data" }
    }
  }
}

output "projects" {
  description = "Projects, for the tenants' credentials."
  value       = module.baseline.projects
}

output "networks" {
  description = "External networks, to adopt in the tenants (existing.networks)."
  value       = module.baseline.networks
}

output "security_groups" {
  description = "Shared security groups, to adopt in the tenants (existing.security_groups)."
  value       = module.baseline.security_groups
}

output "dns_zones" {
  description = "DNS zones, to adopt in the tenants (existing.dns_zones)."
  value       = module.baseline.dns_zones
}
