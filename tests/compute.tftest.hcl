# Flavors and images, with mocked providers: no cloud is needed.

mock_provider "openstack" {}
mock_provider "random" {}

variables {
  baseline = {
    projects = { web = {}, ops = {} }
    flavors = {
      small     = { vcpus = 1, ram = 1024, disk = 10 }
      gpu-large = { vcpus = 8, ram = 32768, disk = 100, is_public = false, projects = ["web", "legacy"], extra_specs = { "hw:cpu_policy" = "dedicated" } }
    }
    images = {
      ubuntu   = { source_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" }
      internal = { source_url = "https://images.example.org/internal.qcow2", visibility = "shared", share_with = ["web", "ops"] }
      silent   = { source_url = "https://images.example.org/silent.qcow2", visibility = "shared", share_with = ["web"], accept = false }
    }
    existing = { projects = { legacy = { id = "00000000000000000000000000000p01" } } }
  }
}

run "model" {
  command = plan

  assert {
    condition     = toset(keys(openstack_compute_flavor_access_v2.this)) == toset(["gpu-large/web", "gpu-large/legacy"])
    error_message = "A restricted flavor gets one access per project, created or adopted."
  }

  assert {
    condition     = openstack_compute_flavor_access_v2.this["gpu-large/legacy"].tenant_id == "00000000000000000000000000000p01"
    error_message = "Access to an adopted project uses its ID."
  }

  assert {
    condition     = openstack_images_image_v2.this["ubuntu"].visibility == "public" && length(openstack_images_image_access_v2.this) == 3
    error_message = "Images are public by default; a shared image gets one member per project."
  }

  assert {
    condition     = toset(keys(openstack_images_image_access_accept_v2.this)) == toset(["internal/web", "internal/ops"])
    error_message = "Memberships are accepted unless accept = false."
  }
}

run "share_with_needs_shared" {
  command = plan

  variables {
    baseline = {
      projects = { web = {} }
      images   = { bad = { source_url = "https://images.example.org/x.qcow2", share_with = ["web"] } }
    }
  }

  expect_failures = [var.baseline]
}

run "projects_need_private_flavor" {
  command = plan

  variables {
    baseline = {
      projects = { web = {} }
      flavors  = { bad = { vcpus = 1, ram = 512, disk = 1, projects = ["web"] } }
    }
  }

  expect_failures = [var.baseline]
}
