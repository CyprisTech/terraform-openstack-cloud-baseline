# Bench scenario: catalogue of shared security groups (spec: first releases, tests of v0.1). Run
# by check-security.sh on the bench host, with DevStack's admin credentials
# (OS_CLOUD=devstack-admin).

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
    # A network every project can put ports on, to attach the groups to.
    networks = {
      bench-sgnet = { share_with = ["*"], type = "geneve", subnets = { main = { cidr = "10.62.0.0/24" } } }
    }
    security_groups = {
      bench-ssh = {
        share_with = ["*"]
        rules      = { ssh = { direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "192.0.2.0/24" } }
      }
      bench-mon = {
        share_with = ["bench-web"]
        rules = {
          node-exporter = { direction = "ingress", protocol = "tcp", port_min = 9100, port_max = 9100, remote_ip_prefix = "198.51.100.0/24" }
          egress-https  = { direction = "egress", protocol = "tcp", port_min = 443, port_max = 443, remote_ip_prefix = "0.0.0.0/0" }
        }
      }
    }
  }
}

output "passwords" {
  value     = module.baseline.passwords
  sensitive = true
}
