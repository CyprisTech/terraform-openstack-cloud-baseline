# The foundation of a landing zone's projects (ADR-0001): identity and projects.
# Every for_each key comes from the input (one plan, no -target).

locals {
  b = var.baseline

  # IDs of every project, user and group, created or adopted, keyed like the input.
  project_ids = merge(
    { for k, p in openstack_identity_project_v3.this : k => p.id },
    { for k, p in local.b.existing.projects : k => coalesce(p.id, try(data.openstack_identity_project_v3.existing[k].id, null)) },
  )
  user_ids = merge(
    { for k, u in openstack_identity_user_v3.this : k => u.id },
    { for k, u in local.b.existing.users : k => coalesce(u.id, try(data.openstack_identity_user_v3.existing[k].id, null)) },
  )
  group_ids = merge(
    { for k, g in openstack_identity_group_v3.this : k => g.id },
    { for k, g in local.b.existing.groups : k => coalesce(g.id, try(data.openstack_identity_group_v3.existing[k].id, null)) },
  )

  # Roles are adopted by name, never created: the deployment of each service creates them.
  roles = toset([for a in local.b.role_assignments : a.role])

  memberships = merge([
    for gk, g in local.b.groups : { for u in g.members : "${gk}/${u}" => { group = gk, user = u } }
  ]...)
}

data "openstack_identity_project_v3" "existing" {
  for_each = { for k, p in local.b.existing.projects : k => p if p.id == null }
  name     = each.value.name
}

data "openstack_identity_user_v3" "existing" {
  for_each = { for k, u in local.b.existing.users : k => u if u.id == null }
  name     = each.value.name
}

data "openstack_identity_group_v3" "existing" {
  for_each = { for k, g in local.b.existing.groups : k => g if g.id == null }
  name     = each.value.name
}

data "openstack_identity_role_v3" "this" {
  for_each = local.roles
  name     = each.key
}
