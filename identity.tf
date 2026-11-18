# Users, groups, memberships and role assignments.

resource "random_password" "user" {
  for_each = { for k, u in local.b.users : k => u if u.password.mode == "generate" }

  length  = 32
  special = false
}

resource "openstack_identity_user_v3" "this" {
  for_each = local.b.users

  name               = each.key
  description        = each.value.description
  enabled            = each.value.enabled
  default_project_id = each.value.default_project == null ? null : local.project_ids[each.value.default_project]
  password = (
    each.value.password.mode == "generate" ? random_password.user[each.key].result :
    each.value.password.mode == "input" ? var.passwords[each.key] :
    null
  )
  extra = each.value.email == null ? null : { email = each.value.email }

  # Keystone never returns a password: a change made by the user causes no difference. Rotate
  # with -replace on the random_password.
}

resource "openstack_identity_group_v3" "this" {
  for_each = local.b.groups

  name        = each.key
  description = each.value.description
}

resource "openstack_identity_user_membership_v3" "this" {
  for_each = local.memberships

  group_id = local.group_ids[each.value.group]
  user_id  = local.user_ids[each.value.user]
}

resource "openstack_identity_role_assignment_v3" "this" {
  for_each = local.b.role_assignments

  project_id = local.project_ids[each.value.project]
  role_id    = data.openstack_identity_role_v3.this[each.value.role].id
  user_id    = each.value.kind == "user" ? local.user_ids[each.value.name] : null
  group_id   = each.value.kind == "group" ? local.group_ids[each.value.name] : null
}
