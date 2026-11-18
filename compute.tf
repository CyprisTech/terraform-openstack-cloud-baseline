# Flavors and images.

resource "openstack_compute_flavor_v2" "this" {
  for_each = local.b.flavors

  name        = each.key
  vcpus       = each.value.vcpus
  ram         = each.value.ram
  disk        = each.value.disk
  ephemeral   = each.value.ephemeral
  swap        = each.value.swap
  flavor_id   = each.value.flavor_id
  is_public   = each.value.is_public
  extra_specs = each.value.extra_specs
}

resource "openstack_compute_flavor_access_v2" "this" {
  for_each = merge([
    for fk, f in local.b.flavors : { for p in f.projects : "${fk}/${p}" => { flavor = fk, project = p } }
  ]...)

  flavor_id = openstack_compute_flavor_v2.this[each.value.flavor].id
  tenant_id = local.project_ids[each.value.project]
}

resource "openstack_images_image_v2" "this" {
  for_each = local.b.images

  name             = each.key
  image_source_url = each.value.source_url
  disk_format      = each.value.disk_format
  container_format = each.value.container_format
  visibility       = each.value.visibility
  min_disk_gb      = each.value.min_disk
  min_ram_mb       = each.value.min_ram
  protected        = each.value.protected
  hidden           = each.value.hidden
  properties       = each.value.properties
}

# Adopted images given by name: the most recent image of that name.
data "openstack_images_image_v2" "existing" {
  for_each    = { for k, i in local.b.existing.images : k => i if i.id == null }
  name        = each.value.name
  most_recent = true
}

locals {
  image_ids = merge(
    { for k, i in openstack_images_image_v2.this : k => i.id },
    { for k, i in local.b.existing.images : k => coalesce(i.id, try(data.openstack_images_image_v2.existing[k].id, null)) },
  )

  image_members = merge([
    for ik, i in merge(local.b.images, local.b.existing.images) : { for p in i.share_with : "${ik}/${p}" => { image = ik, project = p, accept = i.accept } }
  ]...)
}

resource "openstack_images_image_access_v2" "this" {
  for_each = local.image_members

  image_id  = local.image_ids[each.value.image]
  member_id = local.project_ids[each.value.project]
}

# Acceptance on the project's behalf, so that its members see the image.
resource "openstack_images_image_access_accept_v2" "this" {
  for_each = { for k, m in local.image_members : k => m if m.accept }

  image_id  = openstack_images_image_access_v2.this[each.key].image_id
  member_id = openstack_images_image_access_v2.this[each.key].member_id
  status    = "accepted"
}

# Host aggregates and the availability zones they form.
resource "openstack_compute_aggregate_v2" "this" {
  for_each = local.b.aggregates

  name     = each.key
  zone     = each.value.zone
  hosts    = each.value.hosts
  metadata = each.value.metadata
}
