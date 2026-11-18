output "projects" {
  description = "Projects, created or adopted, keyed like the input: { id, name }."
  value = {
    for k, id in local.project_ids : k => {
      id   = id
      name = try(openstack_identity_project_v3.this[k].name, data.openstack_identity_project_v3.existing[k].name, local.b.existing.projects[k].name)
    }
  }
}

output "users" {
  description = "Users, created or adopted, keyed like the input: { id, name }."
  value = {
    for k, id in local.user_ids : k => {
      id   = id
      name = try(openstack_identity_user_v3.this[k].name, data.openstack_identity_user_v3.existing[k].name, local.b.existing.users[k].name)
    }
  }
}

output "groups" {
  description = "Groups, created or adopted, keyed like the input: { id, name }."
  value = {
    for k, id in local.group_ids : k => {
      id   = id
      name = try(openstack_identity_group_v3.this[k].name, data.openstack_identity_group_v3.existing[k].name, local.b.existing.groups[k].name)
    }
  }
}

output "passwords" {
  description = "Generated passwords, keyed by user, to hand over once. They are in the state."
  value       = { for k, p in random_password.user : k => p.result }
  sensitive   = true
}

output "flavors" {
  description = "Flavors keyed like the input: { id, name }."
  value       = { for k, f in openstack_compute_flavor_v2.this : k => { id = f.id, name = f.name } }
}

output "images" {
  description = "Images, created or adopted, keyed like the input: { id, name, visibility, shared_with } (shared_with: project keys; name and visibility null for an image adopted by id)."
  value = merge({
    for k, i in local.b.existing.images : k => {
      id          = local.image_ids[k]
      name        = try(data.openstack_images_image_v2.existing[k].name, i.name)
      visibility  = try(data.openstack_images_image_v2.existing[k].visibility, null)
      shared_with = i.share_with
    }
    }, {
    for k, i in openstack_images_image_v2.this : k => {
      id          = i.id
      name        = i.name
      visibility  = i.visibility
      shared_with = local.b.images[k].share_with
    }
  })
}

output "networks" {
  description = "Networks, created or adopted, keyed like the input, in the shape of the existing.networks input of terraform-openstack-tenant: { id, name, subnets = { <key> = { id, cidr } } } (no subnets for an adopted network)."
  value = merge({
    for k, n in data.openstack_networking_network_v2.existing : k => { id = n.id, name = n.name, subnets = {} }
    }, {
    for nk, n in openstack_networking_network_v2.this : nk => {
      id   = n.id
      name = n.name
      subnets = {
        for sk, s in local.b.networks[nk].subnets : sk => {
          id   = openstack_networking_subnet_v2.this["${nk}/${sk}"].id
          cidr = openstack_networking_subnet_v2.this["${nk}/${sk}"].cidr
        }
      }
    }
  })
}

output "security_groups" {
  description = "Security groups of the catalogue keyed like the input, in the shape of the existing.security_groups input of terraform-openstack-tenant: { id, name }."
  value       = { for k, g in openstack_networking_secgroup_v2.this : k => { id = g.id, name = g.name } }
}

output "dns_zones" {
  description = "DNS zones keyed like the input, in the shape of the existing.dns_zones input of terraform-openstack-tenant: { id, name }."
  value       = { for k, z in openstack_dns_zone_v2.this : k => { id = z.id, name = z.name } }
}

output "address_scopes" {
  description = "Address scopes keyed like the input: { id, name }."
  value       = { for k, a in openstack_networking_addressscope_v2.this : k => { id = a.id, name = a.name } }
}

output "subnet_pools" {
  description = "Subnet pools keyed like the input: { id, name, prefixes }."
  value       = { for k, s in openstack_networking_subnetpool_v2.this : k => { id = s.id, name = s.name, prefixes = s.prefixes } }
}

output "aggregates" {
  description = "Host aggregates keyed like the input: { id, name, zone }."
  value       = { for k, a in openstack_compute_aggregate_v2.this : k => { id = a.id, name = a.name, zone = a.zone } }
}
