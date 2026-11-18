# Address scopes and subnet pools, for planes routed without address translation: a router does
# not translate between subnets of the same scope. Shared through RBAC like the networks.

locals {
  scope_rbac = merge([for k, a in local.b.address_scopes : { for p in a.share_with : "${k}/${p}" => { key = k, project = p } }]...)
  pool_rbac  = merge([for k, s in local.b.subnet_pools : { for p in s.share_with : "${k}/${p}" => { key = k, project = p } }]...)
}

resource "openstack_networking_addressscope_v2" "this" {
  for_each = local.b.address_scopes

  name       = each.key
  ip_version = each.value.ip_version

  # Derived by Neutron from the RBAC policies below.
  lifecycle {
    ignore_changes = [shared]
  }
}

resource "openstack_networking_subnetpool_v2" "this" {
  for_each = local.b.subnet_pools

  name              = each.key
  description       = each.value.description
  prefixes          = each.value.prefixes
  ip_version        = each.value.ip_version
  default_prefixlen = each.value.default_prefixlen
  min_prefixlen     = each.value.min_prefixlen
  max_prefixlen     = each.value.max_prefixlen
  address_scope_id  = each.value.address_scope == null ? null : openstack_networking_addressscope_v2.this[each.value.address_scope].id

  lifecycle {
    ignore_changes = [shared]
  }
}

resource "openstack_networking_rbac_policy_v2" "address_scope" {
  for_each = local.scope_rbac

  action        = "access_as_shared"
  object_type   = "address_scope"
  object_id     = openstack_networking_addressscope_v2.this[each.value.key].id
  target_tenant = each.value.project == "*" ? "*" : local.project_ids[each.value.project]
}

# Neutron shares a pool with a project only once the project has access to the pool's scope.
resource "openstack_networking_rbac_policy_v2" "subnet_pool" {
  for_each = local.pool_rbac

  action        = "access_as_shared"
  object_type   = "subnetpool"
  object_id     = openstack_networking_subnetpool_v2.this[each.value.key].id
  target_tenant = each.value.project == "*" ? "*" : local.project_ids[each.value.project]

  depends_on = [openstack_networking_rbac_policy_v2.address_scope]
}
