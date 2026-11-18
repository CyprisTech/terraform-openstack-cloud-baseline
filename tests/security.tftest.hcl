# Catalogue of shared security groups, with mocked providers: no cloud is needed.

mock_provider "openstack" {}
mock_provider "random" {}

variables {
  baseline = {
    projects = { web = {}, ops = {} }
    security_groups = {
      baseline-ssh = {
        share_with = ["*"]
        rules      = { ssh = { direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "192.0.2.0/24" } }
      }
      monitoring = {
        share_with = ["web", "ops"]
        rules = {
          node-exporter = { direction = "ingress", protocol = "tcp", port_min = 9100, port_max = 9100, remote_ip_prefix = "198.51.100.0/24" }
          egress-any    = { direction = "egress" }
        }
      }
    }
  }
}

run "model" {
  command = plan

  assert {
    condition     = toset(keys(openstack_networking_rbac_policy_v2.security_group)) == toset(["baseline-ssh/*", "monitoring/web", "monitoring/ops"])
    error_message = "One RBAC policy per target, the wildcard included."
  }

  assert {
    condition     = openstack_networking_rbac_policy_v2.security_group["baseline-ssh/*"].target_tenant == "*"
    error_message = "Sharing with every project targets *."
  }

  assert {
    condition     = length(openstack_networking_secgroup_rule_v2.this) == 3 && openstack_networking_secgroup_v2.this["monitoring"].delete_default_rules
    error_message = "Only the rules given; Neutron's default rules removed."
  }
}

run "share_with_required" {
  command = plan

  variables {
    baseline = { security_groups = { lonely = { share_with = [] } } }
  }

  expect_failures = [var.baseline]
}
