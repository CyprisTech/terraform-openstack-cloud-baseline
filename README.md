# terraform-openstack-cloud-baseline

[![CI](https://github.com/CyprisTech/terraform-openstack-cloud-baseline/actions/workflows/ci.yml/badge.svg)](https://github.com/CyprisTech/terraform-openstack-cloud-baseline/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Tested on OpenStack 2026.1](https://img.shields.io/badge/Tested%20on-OpenStack%202026.1%20(DevStack)-red)](docs/testing.md)

OpenTofu and Terraform module that lays the foundation of a landing zone on an OpenStack cloud, with the `admin` role: the projects and their quotas, who may act in them, the flavors and images they use, the external and shared networks they attach to, the security groups and DNS zones they share. Its outputs are what the tenant layer adopts.

> [!NOTE]
> **`v0.1.0`.** Every domain below is tested with mocked providers on OpenTofu and Terraform, and on a disposable DevStack cloud (OpenStack 2026.1) rebuilt from this repository ([bench](tests/devstack/README.md)). Before `v1.0.0`, minor versions may change the interface.

## Who it is for

- **Operators of private OpenStack clouds** who prepare projects for teams, and want that foundation as code, reviewed and repeatable.
- **Platform teams** that build a landing zone with [openstack-multitenant-reference](https://github.com/CyprisTech/openstack-multitenant-reference): this module provides its level 1, the cloud foundation.

On a public cloud, the provider's own IAM and console play this part; the tenant layer works the same either way.

## What it manages

| Domain | Objects |
|---|---|
| Organisation | projects; quotas per service (compute, network, block storage): only those given are managed |
| Identity and access | users (password generated, given, or none for federated users), groups and members, role assignments to users or groups; roles are adopted by name, never created |
| Compute | flavors, public or restricted to projects, with extra specs |
| Images | images with their source, formats and properties; public, community, private, or shared with projects and accepted on their behalf |
| Networks | external and internal networks, provider segments, subnets and host routes, shared with every project or with listed projects |
| Routing | address scopes and subnet pools, shared with projects, for planes routed without address translation; subnets taken from a pool |
| Placement | host aggregates and the availability zones they form |
| Security | a catalogue of security groups owned by the administrator, with only the rules given, shared with projects |
| DNS | zones created for a project (it owns them) or kept by the administrator and shared |

Sharing is always explicit: `share_with = ["*"]` for every project, or a list of project keys. Nothing is shared by default.

Out of scope: the deployment and the operation of OpenStack itself, identity federation and directories, shared file systems and object storage, and anything a project can do with the `member` role (that is the tenant layer, [terraform-openstack-tenant](https://github.com/CyprisTech/terraform-openstack-tenant)).

## Nothing requires it

The tenant layer and the reference adopt existing objects by name or ID, whatever created them: this module, another tool, the cloud's deployment tool, a person. Its outputs have the shape of the tenant layer's `existing` inputs, so that a project's foundation is handed over without lookups.

## Usage

```hcl
provider "openstack" {}   # admin credentials, from clouds.yaml

module "baseline" {
  source  = "CyprisTech/cloud-baseline/openstack" # OpenTofu: cypristech/cloud-baseline/openstack
  version = "~> 0.1"

  baseline = {
    projects = {
      web = { quotas = { compute = { cores = 16, ram = 32768 }, network = { floatingip = 2 } } }
    }
    users  = { alice = { email = "alice@example.org", default_project = "web" } }
    groups = { web-ops = { members = ["alice"] } }
    role_assignments = {
      web-ops-member = { kind = "group", name = "web-ops", project = "web", role = "member" }
      web-ops-lb     = { kind = "group", name = "web-ops", project = "web", role = "load-balancer_member" }
    }
    flavors = { m1-small = { vcpus = 2, ram = 4096, disk = 20 } }
    images  = { ubuntu = { source_url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" } }
    networks = {
      public = {
        external   = true
        share_with = ["*"]
        physnet    = "public"
        subnets    = { main = { cidr = "198.51.100.0/24", enable_dhcp = false } }
      }
    }
    security_groups = {
      baseline-ssh = {
        share_with = ["web"]
        rules      = { ssh = { direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "192.0.2.0/24" } }
      }
    }
    dns_zones = { web = { name = "web.example.org.", email = "dns@example.org", project = "web" } }
  }
}
```

Then, in the tenant's configuration, with the `member` role on its project:

```hcl
tenant = {
  existing = {
    networks        = { public = { id = "<baseline output networks.public.id>" } }
    security_groups = { baseline-ssh = { id = "<baseline output security_groups.baseline-ssh.id>" } }
    dns_zones       = { own = { id = "<baseline output dns_zones.web.id>", name = "web.example.org." } }
  }
  # ...
}
```

Generated passwords come out once through the sensitive output `passwords`; they stay in the state, which must be protected as a secret.

## Existing clouds

Objects owned elsewhere are adopted through `existing` (projects, users, groups, networks created by the deployment tool, images built by a pipeline). Objects created by hand are taken over with `import` blocks: the [takeover guide](docs/takeover.md) gives the address and import ID of each one, tested on the bench.

## Compatibility

| Component | Supported | Tested |
|---|---|---|
| OpenTofu / Terraform | >= 1.9 | OpenTofu 1.13.2; mocked tests on both tools, lowest supported and latest |
| OpenStack provider | `terraform-provider-openstack/openstack` ~> 3.2 | 3.4.0 |
| OpenStack | Keystone v3, Nova, Neutron, Cinder v3, Glance v2; Designate optional | DevStack 2026.1 with OVN ([results](docs/testing.md)) |
| Role | `admin` (or the roles your cloud's policies require for each object) | `admin` |

## Example

[landing-zone-foundation](examples/landing-zone-foundation/README.md): a project for shared services and two tenants, groups and roles, adopted users, flavors and an image, external networks, a shared security group and a DNS zone per tenant.

## Roadmap

| Release | Content | |
|---|---|---|
| `v0.1` | Identity and projects, flavors and images, networks, address scopes and subnet pools, host aggregates and availability zones, security groups, DNS zones; adoption and takeover | released 2026-11-18 |
| `v0.2` | Octavia flavors, flavor profiles and availability zones; load balancer and DNS quotas | |

Specification of the releases: [first releases](docs/specs/first-releases.md).

## Documentation

| Document | Content |
|---|---|
| [Decisions (ADR)](docs/adr/README.md) | [ADR-0001](docs/adr/0001-module-design.md): design of the module (purpose, scope, input model, adoption, outputs, rules, tests) |
| [Takeover](docs/takeover.md) | Taking over objects created by hand |
| [Testing](docs/testing.md) | Test levels, results on the bench, defects the bench found |
| [Changelog](CHANGELOG.md) | Changes per release |
| [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Support](SUPPORT.md) · [Code of conduct](CODE_OF_CONDUCT.md) | How to contribute, report a vulnerability, get help |
| [Specs](docs/specs/README.md) | The first releases, the DevStack bench |
| [DevStack bench](tests/devstack/README.md) | The disposable cloud the tests run on |

## Reference

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_openstack"></a> [openstack](#requirement\_openstack) | ~> 3.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_openstack"></a> [openstack](#provider\_openstack) | ~> 3.2 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

### Resources

| Name | Type |
| ---- | ---- |
| [openstack_blockstorage_quotaset_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/blockstorage_quotaset_v3) | resource |
| [openstack_compute_aggregate_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_aggregate_v2) | resource |
| [openstack_compute_flavor_access_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_flavor_access_v2) | resource |
| [openstack_compute_flavor_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_flavor_v2) | resource |
| [openstack_compute_quotaset_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_quotaset_v2) | resource |
| [openstack_dns_zone_share_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/dns_zone_share_v2) | resource |
| [openstack_dns_zone_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/dns_zone_v2) | resource |
| [openstack_identity_group_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/identity_group_v3) | resource |
| [openstack_identity_project_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/identity_project_v3) | resource |
| [openstack_identity_role_assignment_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/identity_role_assignment_v3) | resource |
| [openstack_identity_user_membership_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/identity_user_membership_v3) | resource |
| [openstack_identity_user_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/identity_user_v3) | resource |
| [openstack_images_image_access_accept_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/images_image_access_accept_v2) | resource |
| [openstack_images_image_access_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/images_image_access_v2) | resource |
| [openstack_images_image_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/images_image_v2) | resource |
| [openstack_networking_addressscope_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_addressscope_v2) | resource |
| [openstack_networking_network_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_network_v2) | resource |
| [openstack_networking_quota_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_quota_v2) | resource |
| [openstack_networking_rbac_policy_v2.address_scope](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2) | resource |
| [openstack_networking_rbac_policy_v2.network](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2) | resource |
| [openstack_networking_rbac_policy_v2.security_group](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2) | resource |
| [openstack_networking_rbac_policy_v2.subnet_pool](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_rbac_policy_v2) | resource |
| [openstack_networking_secgroup_rule_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2) | resource |
| [openstack_networking_subnet_route_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnet_route_v2) | resource |
| [openstack_networking_subnet_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnet_v2) | resource |
| [openstack_networking_subnetpool_v2.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnetpool_v2) | resource |
| [random_password.user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [openstack_identity_group_v3.existing](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/identity_group_v3) | data source |
| [openstack_identity_project_v3.existing](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/identity_project_v3) | data source |
| [openstack_identity_role_v3.this](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/identity_role_v3) | data source |
| [openstack_identity_user_v3.existing](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/identity_user_v3) | data source |
| [openstack_images_image_v2.existing](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2) | data source |
| [openstack_networking_network_v2.existing](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/networking_network_v2) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_baseline"></a> [baseline](#input\_baseline) | Foundation of the landing zone's projects, laid with the admin role (ADR-0001). Every<br/>collection is a map keyed by a stable name; objects reference each other by key, created or<br/>adopted alike.<br/>- projects: description, enabled, tags, and quotas per service (compute, network, volume).<br/>  A quota not given is not managed.<br/>- users: email, enabled, default\_project (a project key), password mode: "generate"<br/>  (default, delivered once by the sensitive output passwords), "input" (from var.passwords)<br/>  or "none" (federated or LDAP users are adopted instead).<br/>- groups: description and members (user keys).<br/>- role\_assignments: kind "user" or "group", name (a user or group key), project (a project<br/>  key), role (the name of an existing role, never created here).<br/>- flavors: vcpus, ram (MiB), disk (GiB), ephemeral, swap, flavor\_id, extra\_specs; public, or<br/>  restricted to projects (project keys, is\_public = false).<br/>- images: source\_url, disk\_format, container\_format, properties, min\_disk, min\_ram,<br/>  protected, hidden; visibility "public" (default), "community", "private" or "shared" with<br/>  share\_with (project keys). A shared image is visible to a project only once accepted:<br/>  accept = true accepts it on the project's behalf.<br/>- networks: external (router gateways and floating IPs) or internal, shared with<br/>  share\_with: ["*"] for every project, or project keys (one RBAC policy each,<br/>  access\_as\_external for an external network, access\_as\_shared for an internal one); physnet, type, segmentation\_id<br/>  for a provider network; mtu; subnets (cidr, gateway\_ip or no\_gateway, enable\_dhcp,<br/>  dns\_nameservers, allocation\_pools, host\_routes).<br/>- address\_scopes and subnet\_pools: for planes routed without address translation; a pool<br/>  belongs to a scope (address\_scope, a key), and a subnet takes its range from a pool<br/>  (subnet\_pool, a key, and prefix\_length, or a cidr inside the pool). Shared like networks.<br/>- aggregates: host aggregates (hosts by compute host name) and the availability zone they<br/>  form (zone), with metadata.<br/>- security\_groups: a catalogue of groups owned by the administrator, shared by RBAC with<br/>  share\_with (["*"] or project keys, required). Only the rules given exist: Neutron's<br/>  default egress rules are removed unless delete\_default\_rules = false.<br/>- dns\_zones: name (with its trailing dot), email, ttl, description; either created for a<br/>  project (project, a project key: the project owns it, the stack keeps reading it), or kept<br/>  by the administrator and shared with projects (share\_with, project keys). Never<br/>  transferred.<br/>- existing: projects, users and groups owned elsewhere, by id or name, that receive quotas,<br/>  roles or memberships; networks (created by the deployment tool) and images (built by an<br/>  image pipeline) that are shared here with share\_with, like the ones created here. | <pre>object({<br/>    projects = optional(map(object({<br/>      description = optional(string, "")<br/>      enabled     = optional(bool, true)<br/>      tags        = optional(list(string), [])<br/>      quotas = optional(object({<br/>        compute = optional(object({<br/>          cores                = optional(number)<br/>          ram                  = optional(number)<br/>          instances            = optional(number)<br/>          key_pairs            = optional(number)<br/>          server_groups        = optional(number)<br/>          server_group_members = optional(number)<br/>        }))<br/>        network = optional(object({<br/>          floatingip          = optional(number)<br/>          network             = optional(number)<br/>          subnet              = optional(number)<br/>          subnetpool          = optional(number)<br/>          port                = optional(number)<br/>          router              = optional(number)<br/>          security_group      = optional(number)<br/>          security_group_rule = optional(number)<br/>          rbac_policy         = optional(number)<br/>        }))<br/>        volume = optional(object({<br/>          volumes              = optional(number)<br/>          snapshots            = optional(number)<br/>          gigabytes            = optional(number)<br/>          per_volume_gigabytes = optional(number)<br/>          backups              = optional(number)<br/>          backup_gigabytes     = optional(number)<br/>          groups               = optional(number)<br/>          volume_type_quota    = optional(map(number))<br/>        }))<br/>      }), {})<br/>    })), {})<br/><br/>    users = optional(map(object({<br/>      email           = optional(string)<br/>      description     = optional(string, "")<br/>      enabled         = optional(bool, true)<br/>      default_project = optional(string)<br/>      password        = optional(object({ mode = optional(string, "generate") }), {})<br/>    })), {})<br/><br/>    groups = optional(map(object({<br/>      description = optional(string, "")<br/>      members     = optional(list(string), [])<br/>    })), {})<br/><br/>    role_assignments = optional(map(object({<br/>      kind    = string<br/>      name    = string<br/>      project = string<br/>      role    = string<br/>    })), {})<br/><br/>    flavors = optional(map(object({<br/>      vcpus       = number<br/>      ram         = number<br/>      disk        = number<br/>      ephemeral   = optional(number, 0)<br/>      swap        = optional(number, 0)<br/>      flavor_id   = optional(string)<br/>      is_public   = optional(bool, true)<br/>      projects    = optional(list(string), [])<br/>      extra_specs = optional(map(string), {})<br/>    })), {})<br/><br/>    images = optional(map(object({<br/>      source_url       = string<br/>      disk_format      = optional(string, "qcow2")<br/>      container_format = optional(string, "bare")<br/>      visibility       = optional(string, "public")<br/>      share_with       = optional(list(string), [])<br/>      accept           = optional(bool, true)<br/>      min_disk         = optional(number)<br/>      min_ram          = optional(number)<br/>      protected        = optional(bool, false)<br/>      hidden           = optional(bool, false)<br/>      properties       = optional(map(string), {})<br/>    })), {})<br/><br/>    networks = optional(map(object({<br/>      external                = optional(bool, false)<br/>      share_with              = optional(list(string), [])<br/>      physnet                 = optional(string)<br/>      type                    = optional(string, "flat")<br/>      segmentation_id         = optional(number)<br/>      mtu                     = optional(number)<br/>      port_security           = optional(bool, true)<br/>      availability_zone_hints = optional(list(string), [])<br/>      description             = optional(string, "")<br/>      subnets = optional(map(object({<br/>        cidr             = optional(string)<br/>        subnet_pool      = optional(string) # key of subnet_pools; with prefix_length, the pool picks the range<br/>        prefix_length    = optional(number)<br/>        ip_version       = optional(number, 4)<br/>        gateway_ip       = optional(string)<br/>        no_gateway       = optional(bool, false)<br/>        enable_dhcp      = optional(bool, true)<br/>        dns_nameservers  = optional(list(string), [])<br/>        allocation_pools = optional(list(object({ start = string, end = string })), [])<br/>        host_routes      = optional(list(object({ destination = string, next_hop = string })), [])<br/>      })), {})<br/>    })), {})<br/><br/>    address_scopes = optional(map(object({<br/>      ip_version = optional(number, 4)<br/>      share_with = optional(list(string), [])<br/>    })), {})<br/><br/>    subnet_pools = optional(map(object({<br/>      prefixes          = list(string)<br/>      address_scope     = optional(string)<br/>      default_prefixlen = optional(number)<br/>      min_prefixlen     = optional(number)<br/>      max_prefixlen     = optional(number)<br/>      ip_version        = optional(number, 4)<br/>      description       = optional(string, "")<br/>      share_with        = optional(list(string), [])<br/>    })), {})<br/><br/>    aggregates = optional(map(object({<br/>      zone     = optional(string)<br/>      hosts    = optional(list(string), [])<br/>      metadata = optional(map(string), {})<br/>    })), {})<br/><br/>    security_groups = optional(map(object({<br/>      description          = optional(string, "")<br/>      share_with           = list(string)<br/>      delete_default_rules = optional(bool, true)<br/>      rules = optional(map(object({<br/>        direction        = string<br/>        ethertype        = optional(string, "IPv4")<br/>        protocol         = optional(string)<br/>        port_min         = optional(number)<br/>        port_max         = optional(number)<br/>        remote_ip_prefix = optional(string)<br/>        description      = optional(string, "")<br/>      })), {})<br/>    })), {})<br/><br/>    dns_zones = optional(map(object({<br/>      name        = string<br/>      email       = string<br/>      ttl         = optional(number)<br/>      description = optional(string, "")<br/>      project     = optional(string)<br/>      share_with  = optional(list(string), [])<br/>    })), {})<br/><br/>    existing = optional(object({<br/>      projects = optional(map(object({ id = optional(string), name = optional(string) })), {})<br/>      users    = optional(map(object({ id = optional(string), name = optional(string) })), {})<br/>      groups   = optional(map(object({ id = optional(string), name = optional(string) })), {})<br/>      # Networks created by the deployment tool, shared with projects here.<br/>      networks = optional(map(object({<br/>        id         = optional(string)<br/>        name       = optional(string)<br/>        external   = optional(bool, false) # decides the RBAC action, as for the networks created here<br/>        share_with = optional(list(string), [])<br/>      })), {})<br/>      # Images built by an image pipeline, shared with projects here.<br/>      images = optional(map(object({<br/>        id         = optional(string)<br/>        name       = optional(string)<br/>        share_with = optional(list(string), [])<br/>        accept     = optional(bool, true)<br/>      })), {})<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_passwords"></a> [passwords](#input\_passwords) | Passwords of the users in mode "input", keyed like baseline.users. They are stored in the state. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_address_scopes"></a> [address\_scopes](#output\_address\_scopes) | Address scopes keyed like the input: { id, name }. |
| <a name="output_aggregates"></a> [aggregates](#output\_aggregates) | Host aggregates keyed like the input: { id, name, zone }. |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | DNS zones keyed like the input, in the shape of the existing.dns\_zones input of terraform-openstack-tenant: { id, name }. |
| <a name="output_flavors"></a> [flavors](#output\_flavors) | Flavors keyed like the input: { id, name }. |
| <a name="output_groups"></a> [groups](#output\_groups) | Groups, created or adopted, keyed like the input: { id, name }. |
| <a name="output_images"></a> [images](#output\_images) | Images, created or adopted, keyed like the input: { id, name, visibility, shared\_with } (shared\_with: project keys; name and visibility null for an image adopted by id). |
| <a name="output_networks"></a> [networks](#output\_networks) | Networks, created or adopted, keyed like the input, in the shape of the existing.networks input of terraform-openstack-tenant: { id, name, subnets = { <key> = { id, cidr } } } (no subnets for an adopted network). |
| <a name="output_passwords"></a> [passwords](#output\_passwords) | Generated passwords, keyed by user, to hand over once. They are in the state. |
| <a name="output_projects"></a> [projects](#output\_projects) | Projects, created or adopted, keyed like the input: { id, name }. |
| <a name="output_security_groups"></a> [security\_groups](#output\_security\_groups) | Security groups of the catalogue keyed like the input, in the shape of the existing.security\_groups input of terraform-openstack-tenant: { id, name }. |
| <a name="output_subnet_pools"></a> [subnet\_pools](#output\_subnet\_pools) | Subnet pools keyed like the input: { id, name, prefixes }. |
| <a name="output_users"></a> [users](#output\_users) | Users, created or adopted, keyed like the input: { id, name }. |
<!-- END_TF_DOCS -->

## License

Apache License 2.0, see [LICENSE](LICENSE).
