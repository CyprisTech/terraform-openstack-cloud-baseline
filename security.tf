# A catalogue of security groups owned by the administrator and shared by RBAC. Projects attach
# them to their ports; they cannot change them.

locals {
  sg_rules = merge([
    for gk, g in local.b.security_groups : { for rk, r in g.rules : "${gk}/${rk}" => merge(r, { group = gk }) }
  ]...)

  sg_rbac = merge([
    for gk, g in local.b.security_groups : { for p in g.share_with : "${gk}/${p}" => { group = gk, project = p } }
  ]...)
}

resource "openstack_networking_secgroup_v2" "this" {
  for_each = local.b.security_groups

  name                 = each.key
  description          = each.value.description
  delete_default_rules = each.value.delete_default_rules
}

resource "openstack_networking_secgroup_rule_v2" "this" {
  for_each = local.sg_rules

  security_group_id = openstack_networking_secgroup_v2.this[each.value.group].id
  direction         = each.value.direction
  ethertype         = each.value.ethertype
  protocol          = each.value.protocol
  port_range_min    = each.value.port_min
  port_range_max    = each.value.port_max
  remote_ip_prefix  = each.value.remote_ip_prefix
  description       = each.value.description
}

resource "openstack_networking_rbac_policy_v2" "security_group" {
  for_each = local.sg_rbac

  action        = "access_as_shared"
  object_id     = openstack_networking_secgroup_v2.this[each.value.group].id
  object_type   = "security_group"
  target_tenant = each.value.project == "*" ? "*" : local.project_ids[each.value.project]
}
