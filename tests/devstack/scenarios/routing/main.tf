# Bench scenario: address scopes, subnet pools and aggregates (spec: first releases, tests of
# v0.1). Run by check-routing.sh on the bench host, with DevStack's admin credentials
# (OS_CLOUD=devstack-admin).

terraform {
  required_version = ">= 1.9"
  required_providers {
    openstack = { source = "terraform-provider-openstack/openstack", version = "~> 3.2" }
    random    = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "openstack" {}

variable "compute_host" {
  description = "Compute host name of the bench, for the aggregate."
  type        = string
}

module "baseline" {
  source = "../../../.."

  baseline = {
    projects = { bench-web = {}, bench-ops = {} }
    users    = { bench-alice = {}, bench-carol = {} }
    role_assignments = {
      alice-web = { kind = "user", name = "bench-alice", project = "bench-web", role = "member" }
      carol-ops = { kind = "user", name = "bench-carol", project = "bench-ops", role = "member" }
    }
    address_scopes = { bench-scope = { share_with = ["bench-web"] } }
    subnet_pools = {
      bench-pool = { prefixes = ["10.80.0.0/16"], default_prefixlen = 24, address_scope = "bench-scope", share_with = ["bench-web"] }
    }
    networks = {
      bench-pooled = { share_with = ["bench-web"], type = "geneve", subnets = { main = { subnet_pool = "bench-pool", prefix_length = 24 } } }
    }
    aggregates = { bench-agg = { zone = "bench-zone", hosts = [var.compute_host], metadata = { bench = "true" } } }
  }
}

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
