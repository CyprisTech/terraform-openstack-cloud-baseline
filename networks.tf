# External and shared networks, their subnets, and their sharing.
# Sharing is explicit and always an RBAC policy: access_as_external for an external network,
# access_as_shared for an internal one, one per project listed, or one for "*" (every project).
# The network's own external and shared attributes are left to Neutron, which derives them from
# the policies: going from every project to a list, or back, changes policies in place.

# Adopted networks, looked up for their ID and name; external is declared in the input, as for
# the networks created here (the data source takes external as a filter, it does not return it).
data "openstack_networking_network_v2" "existing" {
  for_each   = local.b.existing.networks
  network_id = each.value.id
  name       = each.value.id == null ? each.value.name : null
}

locals {
  network_ids = merge(
    { for k, n in openstack_networking_network_v2.this : k => n.id },
    { for k, n in data.openstack_networking_network_v2.existing : k => n.id },
  )

  network_rbac = merge([
    for nk, n in merge(local.b.networks, local.b.existing.networks) : {
      for p in n.share_with : "${nk}/${p}" => {
        network = nk
        project = p
        action  = n.external ? "access_as_external" : "access_as_shared"
      }
    }
  ]...)

  subnets = merge([
    for nk, n in local.b.networks : { for sk, s in n.subnets : "${nk}/${sk}" => merge(s, { network = nk, name = sk }) }
  ]...)

  host_routes = merge([
    for k, s in local.subnets : { for r in s.host_routes : "${k}/${r.destination}" => merge(r, { subnet = k }) }
  ]...)
}

resource "openstack_networking_network_v2" "this" {
  for_each = local.b.networks

  name                    = each.key
  description             = each.value.description
  mtu                     = each.value.mtu
  port_security_enabled   = each.value.port_security
  availability_zone_hints = length(each.value.availability_zone_hints) > 0 ? each.value.availability_zone_hints : null

  # Derived by Neutron from the RBAC policies below.
  lifecycle {
    ignore_changes = [external, shared]
  }

  dynamic "segments" {
    for_each = each.value.physnet == null && each.value.segmentation_id == null ? [] : [1]
    content {
      physical_network = each.value.physnet
      network_type     = each.value.type
      segmentation_id  = each.value.segmentation_id
    }
  }
}

resource "openstack_networking_subnet_v2" "this" {
  for_each = local.subnets

  name            = "${each.value.network}-${each.value.name}"
  network_id      = openstack_networking_network_v2.this[each.value.network].id
  cidr            = each.value.cidr
  subnetpool_id   = each.value.subnet_pool == null ? null : openstack_networking_subnetpool_v2.this[each.value.subnet_pool].id
  prefix_length   = each.value.prefix_length
  ip_version      = each.value.ip_version
  gateway_ip      = each.value.gateway_ip
  no_gateway      = each.value.no_gateway ? true : null # the provider refuses no_gateway = false next to gateway_ip
  enable_dhcp     = each.value.enable_dhcp
  dns_nameservers = each.value.dns_nameservers

  dynamic "allocation_pool" {
    for_each = each.value.allocation_pools
    content {
      start = allocation_pool.value.start
      end   = allocation_pool.value.end
    }
  }
}

resource "openstack_networking_subnet_route_v2" "this" {
  for_each = local.host_routes

  subnet_id        = openstack_networking_subnet_v2.this[each.value.subnet].id
  destination_cidr = each.value.destination
  next_hop         = each.value.next_hop
}

resource "openstack_networking_rbac_policy_v2" "network" {
  for_each = local.network_rbac

  action        = each.value.action
  object_id     = local.network_ids[each.value.network]
  object_type   = "network"
  target_tenant = each.value.project == "*" ? "*" : local.project_ids[each.value.project]
}
