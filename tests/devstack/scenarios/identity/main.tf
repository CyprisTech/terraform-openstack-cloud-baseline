# Bench scenario: identity and projects (spec: first releases, tests of v0.1). Run by
# check-identity.sh on the bench host, with DevStack's admin credentials (OS_CLOUD=devstack-admin).
# The project bench-legacy and the user bench-bob are created beforehand by the script, then
# adopted.

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
    projects = {
      bench-web = {
        description = "Bench: a tenant"
        quotas = {
          compute = { cores = 8, ram = 16384, instances = 4 }
          network = { floatingip = 2, router = 2 }
          volume  = { gigabytes = 100 }
        }
      }
      bench-shared = { description = "Bench: shared services" }
    }
    users = {
      bench-alice = { email = "alice@example.org", default_project = "bench-web" }
    }
    groups = {
      bench-ops = { members = ["bench-alice", "bob"] }
    }
    role_assignments = {
      alice-web  = { kind = "user", name = "bench-alice", project = "bench-web", role = "member" }
      ops-shared = { kind = "group", name = "bench-ops", project = "bench-shared", role = "member" }
      ops-legacy = { kind = "group", name = "bench-ops", project = "legacy", role = "reader" }
    }
    existing = {
      projects = { legacy = { name = "bench-legacy" } }
      users    = { bob = { name = "bench-bob" } }
    }
  }
}

output "projects" { value = module.baseline.projects }
output "users" { value = module.baseline.users }

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
