# Bench scenario: external and shared networks (spec: first releases, tests of v0.1). Run by
# check-networks.sh on the bench host, with DevStack's admin credentials (OS_CLOUD=devstack-admin).
# The physical networks are the bench's simulated planes (planes.sh).

terraform {
  required_version = ">= 1.9"
  required_providers {
    openstack = { source = "terraform-provider-openstack/openstack", version = "~> 3.2" }
    random    = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "openstack" {}

module "baseline" {
  source = "../../../.."

  baseline = {
    projects = { bench-web = {}, bench-ops = {} }
    users    = { bench-alice = {}, bench-carol = {} }
    role_assignments = {
      alice-web = { kind = "user", name = "bench-alice", project = "bench-web", role = "member" }
      carol-ops = { kind = "user", name = "bench-carol", project = "bench-ops", role = "member" }
    }
    # Created beforehand by check-networks.sh, as a deployment tool would.
    existing = {
      networks = { bench-legacy = { name = "bench-legacy-shared", share_with = ["bench-web"] } }
    }
    networks = {
      bench-public = {
        external   = true
        share_with = ["*"]
        physnet    = "publication"
        subnets = { main = {
          cidr             = "198.51.100.0/24", gateway_ip = "198.51.100.1", enable_dhcp = false
          allocation_pools = [{ start = "198.51.100.100", end = "198.51.100.199" }]
        } }
      }
      bench-intranet = {
        external   = true
        share_with = ["bench-web"]
        physnet    = "intranet"
        subnets = { main = {
          cidr             = "192.0.2.0/24", gateway_ip = "192.0.2.1", enable_dhcp = false
          allocation_pools = [{ start = "192.0.2.100", end = "192.0.2.199" }]
        } }
      }
      bench-transit = {
        share_with = ["bench-web"]
        type       = "geneve"
        mtu        = 1400
        subnets = { main = {
          cidr        = "10.60.0.0/24"
          host_routes = [{ destination = "10.70.0.0/16", next_hop = "10.60.0.254" }]
        } }
      }
    }
  }
}

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
