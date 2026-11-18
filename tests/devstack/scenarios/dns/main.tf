# Bench scenario: DNS zones (spec: first releases, tests of v0.1). Run by check-dns.sh on the
# bench host, with DevStack's admin credentials (OS_CLOUD=devstack-admin).

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
    projects = { bench-web = {}, bench-ops = {}, bench-other = {} }
    users    = { bench-alice = {}, bench-carol = {}, bench-dave = {} }
    role_assignments = {
      alice-web  = { kind = "user", name = "bench-alice", project = "bench-web", role = "member" }
      carol-ops  = { kind = "user", name = "bench-carol", project = "bench-ops", role = "member" }
      dave-other = { kind = "user", name = "bench-dave", project = "bench-other", role = "member" }
    }
    dns_zones = {
      web      = { name = "web.bench.example.org.", email = "dns@example.org", project = "bench-web" }
      services = { name = "svc.bench.example.org.", email = "dns@example.org", share_with = ["bench-web", "bench-ops"] }
    }
  }
}

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
