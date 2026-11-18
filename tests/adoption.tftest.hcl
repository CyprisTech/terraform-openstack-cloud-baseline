# Adoption of networks and images owned elsewhere, with mocked providers: no cloud is needed.

mock_provider "openstack" {
  mock_data "openstack_networking_network_v2" {
    defaults = { id = "00000000-0000-0000-0000-0000000000n1" }
  }
  mock_data "openstack_images_image_v2" {
    defaults = { id = "00000000-0000-0000-0000-0000000000i1" }
  }
}
mock_provider "random" {}

variables {
  baseline = {
    projects = { web = {}, ops = {} }
    existing = {
      networks = { provider-net = { name = "provider-net", external = true, share_with = ["web"] } }
      images = {
        golden = { name = "golden-image", share_with = ["web", "ops"] }
        pinned = { id = "00000000-0000-0000-0000-0000000000i2", share_with = ["ops"], accept = false }
      }
    }
  }
}

run "model" {
  command = plan

  assert {
    condition     = keys(openstack_networking_rbac_policy_v2.network) == ["provider-net/web"] && openstack_networking_rbac_policy_v2.network["provider-net/web"].action == "access_as_external"
    error_message = "An adopted external network is shared as external."
  }

  assert {
    condition     = toset(keys(openstack_images_image_access_v2.this)) == toset(["golden/web", "golden/ops", "pinned/ops"]) && openstack_images_image_access_v2.this["pinned/ops"].image_id == "00000000-0000-0000-0000-0000000000i2"
    error_message = "Adopted images, by name or ID, get their members."
  }

  assert {
    condition     = toset(keys(openstack_images_image_access_accept_v2.this)) == toset(["golden/web", "golden/ops"])
    error_message = "Memberships of adopted images are accepted unless accept = false."
  }
}

run "created_and_adopted_network" {
  command = plan

  variables {
    baseline = {
      networks = { dup = {} }
      existing = { networks = { dup = { name = "dup" } } }
    }
  }

  expect_failures = [var.baseline]
}
