# Projects and their quotas. A quota attribute not given is left to the cloud: it is computed by
# the provider, so it causes no difference in the plan.

resource "openstack_identity_project_v3" "this" {
  for_each = local.b.projects

  name        = each.key
  description = each.value.description
  enabled     = each.value.enabled
  tags        = length(each.value.tags) > 0 ? each.value.tags : null
}

resource "openstack_compute_quotaset_v2" "this" {
  for_each = { for k, p in local.b.projects : k => p.quotas.compute if p.quotas.compute != null }

  project_id           = openstack_identity_project_v3.this[each.key].id
  cores                = each.value.cores
  ram                  = each.value.ram
  instances            = each.value.instances
  key_pairs            = each.value.key_pairs
  server_groups        = each.value.server_groups
  server_group_members = each.value.server_group_members
}

resource "openstack_networking_quota_v2" "this" {
  for_each = { for k, p in local.b.projects : k => p.quotas.network if p.quotas.network != null }

  project_id          = openstack_identity_project_v3.this[each.key].id
  floatingip          = each.value.floatingip
  network             = each.value.network
  subnet              = each.value.subnet
  subnetpool          = each.value.subnetpool
  port                = each.value.port
  router              = each.value.router
  security_group      = each.value.security_group
  security_group_rule = each.value.security_group_rule
  rbac_policy         = each.value.rbac_policy
}

resource "openstack_blockstorage_quotaset_v3" "this" {
  for_each = { for k, p in local.b.projects : k => p.quotas.volume if p.quotas.volume != null }

  project_id           = openstack_identity_project_v3.this[each.key].id
  volumes              = each.value.volumes
  snapshots            = each.value.snapshots
  gigabytes            = each.value.gigabytes
  per_volume_gigabytes = each.value.per_volume_gigabytes
  backups              = each.value.backups
  backup_gigabytes     = each.value.backup_gigabytes
  groups               = each.value.groups
  volume_type_quota    = each.value.volume_type_quota
}
