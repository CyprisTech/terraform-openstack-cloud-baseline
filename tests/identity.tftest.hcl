# Identity and projects, with mocked providers: no cloud is needed.

mock_provider "openstack" {
  mock_data "openstack_identity_role_v3" {
    defaults = { id = "00000000000000000000000000000r01" }
  }
}
mock_provider "random" {}

variables {
  baseline = {
    projects = {
      web = {
        description = "Web tenant"
        quotas = {
          compute = { cores = 8, ram = 16384, instances = 4 }
          network = { floatingip = 2, router = 2 }
          volume  = { gigabytes = 100, volume_type_quota = { gigabytes_ssd = 50 } }
        }
      }
      shared = {}
    }
    users = {
      alice = { email = "alice@example.org", default_project = "web" }
      robot = { password = { mode = "input" } }
    }
    groups = {
      ops = { members = ["alice", "bob"] }
    }
    role_assignments = {
      alice-web  = { kind = "user", name = "alice", project = "web", role = "member" }
      ops-web    = { kind = "group", name = "ops", project = "web", role = "member" }
      ops-web-lb = { kind = "group", name = "ops", project = "web", role = "load-balancer_member" }
      ops-legacy = { kind = "group", name = "ops", project = "legacy", role = "reader" }
    }
    existing = {
      projects = { legacy = { id = "00000000000000000000000000000p01" } }
      users    = { bob = { name = "bob" } }
    }
  }
  passwords = { robot = "not-a-real-secret" }
}

run "model" {
  command = plan

  assert {
    condition     = toset(keys(openstack_identity_project_v3.this)) == toset(["web", "shared"])
    error_message = "Projects are created from the keys of baseline.projects only."
  }

  assert {
    condition     = keys(openstack_compute_quotaset_v2.this) == ["web"] && keys(openstack_networking_quota_v2.this) == ["web"] && keys(openstack_blockstorage_quotaset_v3.this) == ["web"]
    error_message = "Quotas are managed only for the services given."
  }

  assert {
    condition     = openstack_compute_quotaset_v2.this["web"].cores == 8 && openstack_blockstorage_quotaset_v3.this["web"].volume_type_quota["gigabytes_ssd"] == "50"
    error_message = "Quotas take the values given. (That the others are left to the cloud is checked on the bench: mocks fill computed values.)"
  }

  assert {
    condition     = keys(random_password.user) == ["alice"]
    error_message = "Only users in mode generate get a generated password."
  }

  assert {
    condition     = toset(keys(openstack_identity_user_membership_v3.this)) == toset(["ops/alice", "ops/bob"])
    error_message = "A membership per group member, created or adopted user alike."
  }

  assert {
    condition     = openstack_identity_role_assignment_v3.this["ops-legacy"].project_id == "00000000000000000000000000000p01" && openstack_identity_role_assignment_v3.this["ops-legacy"].user_id == null
    error_message = "A group gets its role on an adopted project, by its ID."
  }

  assert {
    condition     = toset(keys(data.openstack_identity_role_v3.this)) == toset(["member", "load-balancer_member", "reader"])
    error_message = "Roles are looked up by name, once each."
  }
}

run "unknown_password_mode" {
  command = plan

  variables {
    baseline = { users = { carol = { password = { mode = "random" } } } }
  }

  expect_failures = [var.baseline]
}

run "unknown_reference" {
  command = plan

  variables {
    baseline = {
      users            = { carol = {} }
      role_assignments = { carol-x = { kind = "user", name = "carol", project = "nowhere", role = "member" } }
    }
  }

  expect_failures = [var.baseline]
}

run "created_and_adopted" {
  command = plan

  variables {
    baseline = {
      projects = { web = {} }
      existing = { projects = { web = { name = "web" } } }
    }
  }

  expect_failures = [var.baseline]
}
