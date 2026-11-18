# Bench scenario: flavors and images (spec: first releases, tests of v0.1). Run by
# check-compute.sh on the bench host, with DevStack's admin credentials (OS_CLOUD=devstack-admin).

terraform {
  required_version = ">= 1.9"
  required_providers {
    openstack = { source = "terraform-provider-openstack/openstack", version = "~> 3.2" }
    random    = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "openstack" {}

locals {
  cirros = "https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
}

module "baseline" {
  source = "../../../.."

  baseline = {
    projects = { bench-web = {}, bench-ops = {} }
    users = {
      bench-alice = {}
      bench-carol = {}
    }
    role_assignments = {
      alice-web = { kind = "user", name = "bench-alice", project = "bench-web", role = "member" }
      carol-ops = { kind = "user", name = "bench-carol", project = "bench-ops", role = "member" }
    }
    # Created beforehand by check-compute.sh, as an image pipeline would.
    existing = {
      images = { bench-golden = { name = "bench-golden", share_with = ["bench-web"] } }
    }
    flavors = {
      bench-small      = { vcpus = 1, ram = 512, disk = 1 }
      bench-restricted = { vcpus = 1, ram = 512, disk = 1, is_public = false, projects = ["bench-web"], extra_specs = { "hw:cpu_policy" = "shared" } }
    }
    images = {
      bench-public     = { source_url = local.cirros, properties = { os_distro = "cirros" } }
      bench-shared     = { source_url = local.cirros, visibility = "shared", share_with = ["bench-web"] }
      bench-unaccepted = { source_url = local.cirros, visibility = "shared", share_with = ["bench-ops"], accept = false }
    }
  }
}

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
