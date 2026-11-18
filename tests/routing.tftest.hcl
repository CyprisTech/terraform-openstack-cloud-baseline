# Address scopes, subnet pools and aggregates, with mocked providers: no cloud is needed.

mock_provider "openstack" {}
mock_provider "random" {}

variables {
  baseline = {
    projects       = { web = {}, ops = {} }
    address_scopes = { routed = { share_with = ["*"] } }
    subnet_pools = {
      tenants = { prefixes = ["10.80.0.0/16"], default_prefixlen = 24, address_scope = "routed", share_with = ["*"] }
    }
    networks = {
      transit = { subnets = { main = { subnet_pool = "tenants", prefix_length = 26 } } }
    }
    aggregates = { zone-a = { zone = "zone-a", hosts = ["compute-1"], metadata = { ssd = "true" } } }
  }
}

run "model" {
  command = plan

  assert {
    condition     = keys(openstack_networking_rbac_policy_v2.address_scope) == ["routed/*"] && keys(openstack_networking_rbac_policy_v2.subnet_pool) == ["tenants/*"]
    error_message = "One RBAC policy per target, for scopes and pools alike."
  }

  assert {
    condition     = openstack_networking_rbac_policy_v2.subnet_pool["tenants/*"].object_type == "subnetpool" && openstack_networking_rbac_policy_v2.subnet_pool["tenants/*"].target_tenant == "*"
    error_message = "A pool shared with every project targets *."
  }

  assert {
    condition     = openstack_networking_subnet_v2.this["transit/main"].prefix_length == 26
    error_message = "A subnet taken from a pool has the prefix length given."
  }

  assert {
    condition     = openstack_compute_aggregate_v2.this["zone-a"].zone == "zone-a" && openstack_compute_aggregate_v2.this["zone-a"].hosts == toset(["compute-1"])
    error_message = "An aggregate with its hosts and zone."
  }
}

run "subnet_needs_range_or_pool" {
  command = plan

  variables {
    baseline = { networks = { bad = { subnets = { main = {} } } } }
  }

  expect_failures = [var.baseline]
}

run "pool_wider_than_scope" {
  command = plan

  variables {
    baseline = {
      projects       = { web = {}, ops = {} }
      address_scopes = { routed = { share_with = ["web"] } }
      subnet_pools   = { tenants = { prefixes = ["10.80.0.0/16"], address_scope = "routed", share_with = ["web", "ops"] } }
    }
  }

  expect_failures = [var.baseline]
}

run "unknown_scope" {
  command = plan

  variables {
    baseline = { subnet_pools = { bad = { prefixes = ["10.0.0.0/8"], address_scope = "nowhere" } } }
  }

  expect_failures = [var.baseline]
}

# The pool's ID is known after apply only: Terraform 1.17 refuses an unknown condition value in a plan.
run "subnet_from_pool" {
  command = apply

  assert {
    condition     = openstack_networking_subnet_v2.this["transit/main"].subnetpool_id == openstack_networking_subnetpool_v2.this["tenants"].id
    error_message = "A subnet takes its range from its pool."
  }
}
