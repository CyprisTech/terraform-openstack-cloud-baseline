# DNS zones. A zone used by one project is created for it: the provider sends the sudo header,
# the project owns the zone and writes its records, and this stack keeps reading it. A zone used
# by several projects stays the administrator's and is shared with them. A zone is never
# transferred: after a transfer, the stack that created it can no longer read it.

resource "openstack_dns_zone_v2" "this" {
  for_each = local.b.dns_zones

  name        = each.value.name
  email       = each.value.email
  ttl         = each.value.ttl
  description = each.value.description
  type        = "PRIMARY"
  project_id  = each.value.project == null ? null : local.project_ids[each.value.project]
}

resource "openstack_dns_zone_share_v2" "this" {
  for_each = merge([
    for zk, z in local.b.dns_zones : { for p in z.share_with : "${zk}/${p}" => { zone = zk, project = p } }
  ]...)

  zone_id           = openstack_dns_zone_v2.this[each.value.zone].id
  target_project_id = local.project_ids[each.value.project]
}
