# External and shared networks, with mocked providers: no cloud is needed.

mock_provider "openstack" {}
mock_provider "random" {}

variables {
  baseline = {
    projects = { web = {}, ops = {} }
    networks = {
      public = {
        external   = true
        share_with = ["*"]
        physnet    = "public"
        subnets    = { main = { cidr = "198.51.100.0/24", enable_dhcp = false } }
      }
      intranet = {
        external   = true
        share_with = ["web", "legacy"]
        physnet    = "intranet"
        subnets    = { main = { cidr = "192.0.2.0/24", host_routes = [{ destination = "10.0.0.0/8", next_hop = "192.0.2.254" }] } }
      }
      transit = {
        share_with = ["web"]
        type       = "geneve"
        subnets    = { a = { cidr = "10.60.0.0/24" }, b = { cidr = "10.61.0.0/24" } }
      }
    }
    existing = { projects = { legacy = { id = "00000000000000000000000000000p01" } } }
  }
}

run "model" {
  command = plan

  assert {
    condition     = toset(keys(openstack_networking_rbac_policy_v2.network)) == toset(["public/*", "intranet/web", "intranet/legacy", "transit/web"])
    error_message = "One RBAC policy per project listed, or one for every project."
  }

  assert {
    condition     = openstack_networking_rbac_policy_v2.network["public/*"].target_tenant == "*" && openstack_networking_rbac_policy_v2.network["public/*"].action == "access_as_external"
    error_message = "Every project is the target *."
  }

  assert {
    condition     = openstack_networking_rbac_policy_v2.network["intranet/web"].action == "access_as_external" && openstack_networking_rbac_policy_v2.network["transit/web"].action == "access_as_shared"
    error_message = "External networks are shared as external, internal ones as shared."
  }

  assert {
    condition     = openstack_networking_rbac_policy_v2.network["intranet/legacy"].target_tenant == "00000000000000000000000000000p01"
    error_message = "An adopted project is targeted by its ID."
  }

  assert {
    condition     = length(openstack_networking_subnet_v2.this) == 4 && keys(openstack_networking_subnet_route_v2.this) == ["intranet/main/10.0.0.0/8"]
    error_message = "One subnet per entry, one route per host route."
  }
}

run "wildcard_alone" {
  command = plan

  variables {
    baseline = {
      projects = { web = {} }
      networks = { bad = { share_with = ["*", "web"] } }
    }
  }

  expect_failures = [var.baseline]
}
