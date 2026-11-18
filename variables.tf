variable "baseline" {
  description = <<-EOT
    Foundation of the landing zone's projects, laid with the admin role (ADR-0001). Every
    collection is a map keyed by a stable name; objects reference each other by key, created or
    adopted alike.
    - projects: description, enabled, tags, and quotas per service (compute, network, volume).
      A quota not given is not managed.
    - users: email, enabled, default_project (a project key), password mode: "generate"
      (default, delivered once by the sensitive output passwords), "input" (from var.passwords)
      or "none" (federated or LDAP users are adopted instead).
    - groups: description and members (user keys).
    - role_assignments: kind "user" or "group", name (a user or group key), project (a project
      key), role (the name of an existing role, never created here).
    - flavors: vcpus, ram (MiB), disk (GiB), ephemeral, swap, flavor_id, extra_specs; public, or
      restricted to projects (project keys, is_public = false).
    - images: source_url, disk_format, container_format, properties, min_disk, min_ram,
      protected, hidden; visibility "public" (default), "community", "private" or "shared" with
      share_with (project keys). A shared image is visible to a project only once accepted:
      accept = true accepts it on the project's behalf.
    - networks: external (router gateways and floating IPs) or internal, shared with
      share_with: ["*"] for every project, or project keys (one RBAC policy each,
      access_as_external for an external network, access_as_shared for an internal one); physnet, type, segmentation_id
      for a provider network; mtu; subnets (cidr, gateway_ip or no_gateway, enable_dhcp,
      dns_nameservers, allocation_pools, host_routes).
    - address_scopes and subnet_pools: for planes routed without address translation; a pool
      belongs to a scope (address_scope, a key), and a subnet takes its range from a pool
      (subnet_pool, a key, and prefix_length, or a cidr inside the pool). Shared like networks.
    - aggregates: host aggregates (hosts by compute host name) and the availability zone they
      form (zone), with metadata.
    - security_groups: a catalogue of groups owned by the administrator, shared by RBAC with
      share_with (["*"] or project keys, required). Only the rules given exist: Neutron's
      default egress rules are removed unless delete_default_rules = false.
    - dns_zones: name (with its trailing dot), email, ttl, description; either created for a
      project (project, a project key: the project owns it, the stack keeps reading it), or kept
      by the administrator and shared with projects (share_with, project keys). Never
      transferred.
    - existing: projects, users and groups owned elsewhere, by id or name, that receive quotas,
      roles or memberships; networks (created by the deployment tool) and images (built by an
      image pipeline) that are shared here with share_with, like the ones created here.
  EOT
  type = object({
    projects = optional(map(object({
      description = optional(string, "")
      enabled     = optional(bool, true)
      tags        = optional(list(string), [])
      quotas = optional(object({
        compute = optional(object({
          cores                = optional(number)
          ram                  = optional(number)
          instances            = optional(number)
          key_pairs            = optional(number)
          server_groups        = optional(number)
          server_group_members = optional(number)
        }))
        network = optional(object({
          floatingip          = optional(number)
          network             = optional(number)
          subnet              = optional(number)
          subnetpool          = optional(number)
          port                = optional(number)
          router              = optional(number)
          security_group      = optional(number)
          security_group_rule = optional(number)
          rbac_policy         = optional(number)
        }))
        volume = optional(object({
          volumes              = optional(number)
          snapshots            = optional(number)
          gigabytes            = optional(number)
          per_volume_gigabytes = optional(number)
          backups              = optional(number)
          backup_gigabytes     = optional(number)
          groups               = optional(number)
          volume_type_quota    = optional(map(number))
        }))
      }), {})
    })), {})

    users = optional(map(object({
      email           = optional(string)
      description     = optional(string, "")
      enabled         = optional(bool, true)
      default_project = optional(string)
      password        = optional(object({ mode = optional(string, "generate") }), {})
    })), {})

    groups = optional(map(object({
      description = optional(string, "")
      members     = optional(list(string), [])
    })), {})

    role_assignments = optional(map(object({
      kind    = string
      name    = string
      project = string
      role    = string
    })), {})

    flavors = optional(map(object({
      vcpus       = number
      ram         = number
      disk        = number
      ephemeral   = optional(number, 0)
      swap        = optional(number, 0)
      flavor_id   = optional(string)
      is_public   = optional(bool, true)
      projects    = optional(list(string), [])
      extra_specs = optional(map(string), {})
    })), {})

    images = optional(map(object({
      source_url       = string
      disk_format      = optional(string, "qcow2")
      container_format = optional(string, "bare")
      visibility       = optional(string, "public")
      share_with       = optional(list(string), [])
      accept           = optional(bool, true)
      min_disk         = optional(number)
      min_ram          = optional(number)
      protected        = optional(bool, false)
      hidden           = optional(bool, false)
      properties       = optional(map(string), {})
    })), {})

    networks = optional(map(object({
      external                = optional(bool, false)
      share_with              = optional(list(string), [])
      physnet                 = optional(string)
      type                    = optional(string, "flat")
      segmentation_id         = optional(number)
      mtu                     = optional(number)
      port_security           = optional(bool, true)
      availability_zone_hints = optional(list(string), [])
      description             = optional(string, "")
      subnets = optional(map(object({
        cidr             = optional(string)
        subnet_pool      = optional(string) # key of subnet_pools; with prefix_length, the pool picks the range
        prefix_length    = optional(number)
        ip_version       = optional(number, 4)
        gateway_ip       = optional(string)
        no_gateway       = optional(bool, false)
        enable_dhcp      = optional(bool, true)
        dns_nameservers  = optional(list(string), [])
        allocation_pools = optional(list(object({ start = string, end = string })), [])
        host_routes      = optional(list(object({ destination = string, next_hop = string })), [])
      })), {})
    })), {})

    address_scopes = optional(map(object({
      ip_version = optional(number, 4)
      share_with = optional(list(string), [])
    })), {})

    subnet_pools = optional(map(object({
      prefixes          = list(string)
      address_scope     = optional(string)
      default_prefixlen = optional(number)
      min_prefixlen     = optional(number)
      max_prefixlen     = optional(number)
      ip_version        = optional(number, 4)
      description       = optional(string, "")
      share_with        = optional(list(string), [])
    })), {})

    aggregates = optional(map(object({
      zone     = optional(string)
      hosts    = optional(list(string), [])
      metadata = optional(map(string), {})
    })), {})

    security_groups = optional(map(object({
      description          = optional(string, "")
      share_with           = list(string)
      delete_default_rules = optional(bool, true)
      rules = optional(map(object({
        direction        = string
        ethertype        = optional(string, "IPv4")
        protocol         = optional(string)
        port_min         = optional(number)
        port_max         = optional(number)
        remote_ip_prefix = optional(string)
        description      = optional(string, "")
      })), {})
    })), {})

    dns_zones = optional(map(object({
      name        = string
      email       = string
      ttl         = optional(number)
      description = optional(string, "")
      project     = optional(string)
      share_with  = optional(list(string), [])
    })), {})

    existing = optional(object({
      projects = optional(map(object({ id = optional(string), name = optional(string) })), {})
      users    = optional(map(object({ id = optional(string), name = optional(string) })), {})
      groups   = optional(map(object({ id = optional(string), name = optional(string) })), {})
      # Networks created by the deployment tool, shared with projects here.
      networks = optional(map(object({
        id         = optional(string)
        name       = optional(string)
        external   = optional(bool, false) # decides the RBAC action, as for the networks created here
        share_with = optional(list(string), [])
      })), {})
      # Images built by an image pipeline, shared with projects here.
      images = optional(map(object({
        id         = optional(string)
        name       = optional(string)
        share_with = optional(list(string), [])
        accept     = optional(bool, true)
      })), {})
    }), {})
  })
  default = {}

  validation {
    condition = alltrue([
      for k, u in var.baseline.users : contains(["generate", "input", "none"], u.password.mode)
    ])
    error_message = "users.*.password.mode must be generate, input or none."
  }

  validation {
    condition = alltrue(flatten([
      [for k, f in var.baseline.flavors : [for p in f.projects : contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)]],
      [for k, f in var.baseline.flavors : f.is_public == false || length(f.projects) == 0],
    ]))
    error_message = "flavors.*.projects are project keys, for a flavor with is_public = false."
  }

  validation {
    condition = alltrue(flatten([
      [for k, i in var.baseline.images : contains(["public", "community", "private", "shared"], i.visibility)],
      [for k, i in var.baseline.images : i.visibility == "shared" || length(i.share_with) == 0],
      [for k, i in merge(var.baseline.images, var.baseline.existing.images) : [for p in i.share_with : contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)]],
    ]))
    error_message = "images.*.visibility is public, community, private or shared; share_with (project keys) only with shared."
  }

  validation {
    condition = alltrue(flatten([
      [for k, n in merge(var.baseline.networks, var.baseline.existing.networks) : !contains(n.share_with, "*") || length(n.share_with) == 1],
      [for k, n in merge(var.baseline.networks, var.baseline.existing.networks) : [for p in n.share_with : p == "*" || contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)]],
      [for k, n in var.baseline.networks : contains(["flat", "vlan", "vxlan", "geneve"], n.type)],
      [for k, n in var.baseline.networks : [for sk, s in n.subnets : (s.cidr != null || s.subnet_pool != null) && (s.subnet_pool == null || contains(keys(var.baseline.subnet_pools), coalesce(s.subnet_pool, "-")))]],
      [for k, p in var.baseline.subnet_pools : p.address_scope == null || contains(keys(var.baseline.address_scopes), coalesce(p.address_scope, "-"))],
      [for k, p in var.baseline.subnet_pools : p.address_scope == null || alltrue([for t in p.share_with : contains(try(var.baseline.address_scopes[p.address_scope].share_with, []), t) || contains(try(var.baseline.address_scopes[p.address_scope].share_with, []), "*")])],
      [for o in concat(values(var.baseline.address_scopes), values(var.baseline.subnet_pools)) : (!contains(o.share_with, "*") || length(o.share_with) == 1) && alltrue([for p in o.share_with : p == "*" || contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)])],
    ]))
    error_message = "networks.*.share_with is [\"*\"] alone or project keys; networks.*.type is flat, vlan, vxlan or geneve; a subnet has a cidr or a subnet_pool key; a pool's address_scope is a key; address scopes and pools share with [\"*\"] alone or project keys, a pool only with projects its scope is shared with."
  }

  validation {
    condition = alltrue(flatten([
      [for k, g in var.baseline.security_groups : length(g.share_with) > 0 && (!contains(g.share_with, "*") || length(g.share_with) == 1)],
      [for k, g in var.baseline.security_groups : [for p in g.share_with : p == "*" || contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)]],
      [for k, g in var.baseline.security_groups : [for r in values(g.rules) : contains(["ingress", "egress"], r.direction) && contains(["IPv4", "IPv6"], r.ethertype)]],
    ]))
    error_message = "security_groups.*.share_with is [\"*\"] alone or project keys; rules have direction ingress or egress and ethertype IPv4 or IPv6."
  }

  validation {
    condition = alltrue(flatten([
      [for k, z in var.baseline.dns_zones : endswith(z.name, ".")],
      [for k, z in var.baseline.dns_zones : z.project == null || length(z.share_with) == 0],
      [for k, z in var.baseline.dns_zones : [for p in concat(z.project == null ? [] : [z.project], z.share_with) : contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), p)]],
    ]))
    error_message = "dns_zones.*.name ends with a dot; project and share_with are exclusive and name project keys."
  }

  validation {
    condition = alltrue([
      for k, a in var.baseline.role_assignments : contains(["user", "group"], a.kind)
    ])
    error_message = "role_assignments.*.kind must be user or group."
  }

  validation {
    condition = alltrue(flatten([
      for kind in ["projects", "users", "groups", "networks", "images"] : [
        for k, o in var.baseline.existing[kind] : (o.id == null) != (o.name == null)
      ]
    ]))
    error_message = "Each existing object needs exactly one of id or name."
  }

  validation {
    condition = alltrue([
      for k, a in var.baseline.role_assignments :
      contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), a.project) &&
      contains(a.kind == "user" ? concat(keys(var.baseline.users), keys(var.baseline.existing.users)) : concat(keys(var.baseline.groups), keys(var.baseline.existing.groups)), a.name)
    ])
    error_message = "role_assignments.*.project must be a project key and name a user or group key, created or existing."
  }

  validation {
    condition = alltrue(flatten([
      [for k, g in var.baseline.groups : [for m in g.members : contains(concat(keys(var.baseline.users), keys(var.baseline.existing.users)), m)]],
      [for k, u in var.baseline.users : u.default_project == null || contains(concat(keys(var.baseline.projects), keys(var.baseline.existing.projects)), coalesce(u.default_project, "-"))],
    ]))
    error_message = "groups.*.members must be user keys and users.*.default_project a project key, created or existing."
  }

  validation {
    condition     = length(setintersection(keys(var.baseline.networks), keys(var.baseline.existing.networks))) == 0 && length(setintersection(keys(var.baseline.images), keys(var.baseline.existing.images))) == 0 && length(setintersection(keys(var.baseline.projects), keys(var.baseline.existing.projects))) == 0 && length(setintersection(keys(var.baseline.users), keys(var.baseline.existing.users))) == 0 && length(setintersection(keys(var.baseline.groups), keys(var.baseline.existing.groups))) == 0
    error_message = "A key is either created or adopted (existing), not both."
  }
}

variable "passwords" {
  description = "Passwords of the users in mode \"input\", keyed like baseline.users. They are stored in the state."
  type        = map(string)
  default     = {}
  sensitive   = true
}
