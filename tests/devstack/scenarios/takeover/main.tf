# Bench scenario: taking over objects created by hand (docs/takeover.md). check-takeover.sh
# creates them with the CLI, writes their IDs to ids.auto.tfvars.json, then this configuration
# describes them and imports them.

terraform {
  required_version = ">= 1.9"
  required_providers {
    openstack = { source = "terraform-provider-openstack/openstack", version = "~> 3.2" }
    random    = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "openstack" {}

variable "ids" {
  description = "IDs of the objects to take over, written by check-takeover.sh."
  type        = map(string)
}

variable "region" {
  description = "Region of the quotas."
  type        = string
  default     = "RegionOne"
}

module "baseline" {
  source = "../../../.."

  baseline = {
    projects = {
      bench-legacy-web = { description = "", quotas = { compute = { cores = 10 } } }
    }
    users  = { bench-erin = { password = { mode = "none" } } }
    groups = { bench-team = { members = ["bench-erin"] } }
    role_assignments = {
      team-web = { kind = "group", name = "bench-team", project = "bench-legacy-web", role = "member" }
    }
    flavors = { bench-legacy = { vcpus = 1, ram = 512, disk = 1 } }
    networks = {
      bench-legacy-net = { share_with = ["bench-legacy-web"], type = "geneve", subnets = { main = { cidr = "10.63.0.0/24" } } }
      bench-legacy-ext = {
        external   = true
        share_with = ["*"]
        physnet    = "routed"
        subnets    = { main = { cidr = "100.64.0.0/24", gateway_ip = "100.64.0.1", enable_dhcp = false } }
      }
    }
    security_groups = {
      bench-legacy-ssh = {
        share_with           = ["bench-legacy-web"]
        delete_default_rules = false # created by hand with Neutron's default egress rules
        rules                = { ssh = { direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "192.0.2.0/24" } }
      }
    }
    dns_zones = {
      legacy = { name = "legacy.bench.example.org.", email = "dns@example.org", project = "bench-legacy-web" }
    }
  }
}

import {
  to = module.baseline.openstack_identity_project_v3.this["bench-legacy-web"]
  id = var.ids.project
}

import {
  to = module.baseline.openstack_compute_quotaset_v2.this["bench-legacy-web"]
  id = "${var.ids.project}/${var.region}"
}

import {
  to = module.baseline.openstack_identity_user_v3.this["bench-erin"]
  id = var.ids.user
}

import {
  to = module.baseline.openstack_identity_group_v3.this["bench-team"]
  id = var.ids.group
}

import {
  to = module.baseline.openstack_identity_user_membership_v3.this["bench-team/bench-erin"]
  id = "${var.ids.user}/${var.ids.group}"
}

# domain/project/group/user/role, empty fields where absent
import {
  to = module.baseline.openstack_identity_role_assignment_v3.this["team-web"]
  id = "/${var.ids.project}/${var.ids.group}//${var.ids.role}"
}

import {
  to = module.baseline.openstack_compute_flavor_v2.this["bench-legacy"]
  id = var.ids.flavor
}

import {
  to = module.baseline.openstack_networking_network_v2.this["bench-legacy-net"]
  id = var.ids.network
}

import {
  to = module.baseline.openstack_networking_subnet_v2.this["bench-legacy-net/main"]
  id = var.ids.subnet
}

import {
  to = module.baseline.openstack_networking_rbac_policy_v2.network["bench-legacy-net/bench-legacy-web"]
  id = var.ids.network_rbac
}

import {
  to = module.baseline.openstack_networking_network_v2.this["bench-legacy-ext"]
  id = var.ids.external_network
}

import {
  to = module.baseline.openstack_networking_subnet_v2.this["bench-legacy-ext/main"]
  id = var.ids.external_subnet
}

# The policy Neutron created itself when the network was made external.
import {
  to = module.baseline.openstack_networking_rbac_policy_v2.network["bench-legacy-ext/*"]
  id = var.ids.external_rbac
}

import {
  to = module.baseline.openstack_networking_secgroup_v2.this["bench-legacy-ssh"]
  id = var.ids.security_group
}

import {
  to = module.baseline.openstack_networking_secgroup_rule_v2.this["bench-legacy-ssh/ssh"]
  id = var.ids.security_group_rule
}

import {
  to = module.baseline.openstack_networking_rbac_policy_v2.security_group["bench-legacy-ssh/bench-legacy-web"]
  id = var.ids.security_group_rbac
}

# zone_id:project_id for a zone owned by another project (the provider's documentation says "/",
# its code splits on ":").
import {
  to = module.baseline.openstack_dns_zone_v2.this["legacy"]
  id = "${var.ids.zone}:${var.ids.project}"
}
