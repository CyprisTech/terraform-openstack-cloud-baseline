# DNS zones, with mocked providers: no cloud is needed.

mock_provider "openstack" {}
mock_provider "random" {}

variables {
  baseline = {
    projects = { web = {}, ops = {} }
    dns_zones = {
      web      = { name = "web.example.org.", email = "dns@example.org", project = "web" }
      services = { name = "svc.example.org.", email = "dns@example.org", share_with = ["web", "ops"] }
    }
  }
}

run "model" {
  command = plan

  assert {
    condition     = toset(keys(openstack_dns_zone_share_v2.this)) == toset(["services/web", "services/ops"])
    error_message = "One share per project of a shared zone (the owner is checked on the bench: mocks fill project_id)."
  }
}

run "exclusive" {
  command = plan

  variables {
    baseline = {
      projects  = { web = {} }
      dns_zones = { bad = { name = "bad.example.org.", email = "dns@example.org", project = "web", share_with = ["web"] } }
    }
  }

  expect_failures = [var.baseline]
}

run "trailing_dot" {
  command = plan

  variables {
    baseline = { dns_zones = { bad = { name = "bad.example.org", email = "dns@example.org" } } }
  }

  expect_failures = [var.baseline]
}
