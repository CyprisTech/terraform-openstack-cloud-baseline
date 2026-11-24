# ADR-0001: Design of the `cloud-baseline` module

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** maintainers
- **Refines:** [terraform-openstack-tenant ADR-0001](https://github.com/CyprisTech/terraform-openstack-tenant/blob/main/docs/adr/0001-module-design.md) D1 (three layers) and D4 (`cloud-baseline` input model), which planned this module inside that repository

## Context

A landing zone on OpenStack has a foundation that only the cloud operator can lay, with the `admin` role: the projects and their quotas, who may act in them, the flavors and images they may use, the external and shared networks they attach to, the security groups and DNS zones they share. [openstack-multitenant-reference](https://github.com/CyprisTech/openstack-multitenant-reference) calls it level 1 and consumes it; [terraform-openstack-tenant](https://github.com/CyprisTech/terraform-openstack-tenant) builds the tenants on top of it with the `member` role.

Configuration tools already exist that describe a whole cloud, often generated from its current state. They answer a different need: mirroring and maintaining the configuration of one cloud. This module answers another: laying the foundation a landing zone design expects, and handing it to the tenant layer by contract.

## Options considered

1. **Keep the module in terraform-openstack-tenant**, as planned. One repository, but two audiences (consumers of a cloud with `member`, operators with `admin`) under a registry name that says "tenant", and one version for two release cycles.
2. **Contribute to an existing cloud configuration tool.** Less code to maintain, but the needs here change its model (role assignments to users and groups, adoption of existing objects, explicit sharing of every object, zones created for a project, an output contract), and its purpose stays the configuration of a whole cloud.
3. **A separate module, designed as the foundation of a landing zone** (chosen).

## Decision

### D1. Purpose: the foundation of a landing zone

- The module lays what a landing zone's projects receive from the cloud operator, and exposes it through an output contract that the tenant layer and the reference consume.
- It is not a tool to describe every object of a cloud: what the landing zone design does not need stays out (D2).
- **Interoperability.** Nothing requires this module: the tenant layer and the reference adopt existing objects by name or ID, whatever created them (another tool, a deployment tool, a person).

### D2. Scope

In scope, with the `admin` role:

| Domain | Objects |
|---|---|
| Organisation | projects and their quotas (compute, network, block storage, and, with `v0.2`, the services' own quotas: load balancers, DNS) |
| Identity and access | users, groups and memberships, role assignments to users or groups on projects; the roles themselves are adopted by name, never created: the deployment of each service creates them |
| Compute | flavors, public or restricted to projects; host aggregates and availability zones |
| Images | images with their source, formats, properties and visibility; sharing with projects |
| Networks | external and shared networks, their subnets; sharing by RBAC with explicit targets; address scopes and subnet pools, for planes routed without address translation |
| Security | a catalogue of security groups shared by RBAC with explicit targets |
| DNS | zones created for a project, or kept by the operator and shared with projects |

Out of scope: the deployment and the operation of OpenStack itself; identity federation and LDAP back ends (configured with the cloud); shared file systems and object storage; domains other than the default one until a user needs them; anything a project can do with the `member` role (the tenant layer).

### D3. Input model

One object, `baseline`, whose collections are maps keyed by stable names; objects reference each other by key. The model of terraform-openstack-tenant ADR-0001 D4 is the starting point:

```hcl
baseline = {
  projects = {
    demo = {
      description?, enabled? = true, tags? = []
      quotas? = { compute? = {...}, network? = {...}, volume? = {...} }   # load balancer and DNS quotas: v0.2
    }
  }
  users?            = { alice = { email?, enabled? = true, default_project?, password? = { mode = "generate" } } }
  groups?           = { ops = { description?, members? = ["alice"] } }
  role_assignments? = {
    alice-demo   = { kind = "user", name = "alice", project = "demo", role = "member" }
    lb-ops-demo  = { kind = "group", name = "ops", project = "demo", role = "load-balancer_member" }
  }

  aggregates? = { zone-a = { zone = "zone-a", hosts = ["..."], metadata? = {} } }
  flavors?    = { m1-small = { vcpus, ram, disk, ephemeral?, is_public? = true, projects? = [], extra_specs? = {} } }
  images?     = { ubuntu = { source_url, disk_format, container_format, visibility? = "public", share_with? = [], properties? = {} } }

  networks? = {
    transit = {
      external? = false, share_with? = []                 # RBAC targets, explicit
      physnet?, type? = "flat", segmentation_id?, mtu?, availability_zone_hints? = []
      subnets = { main = { cidr?, subnet_pool?, gateway_ip?, enable_dhcp?, dns_nameservers?, allocation_pools?, host_routes? } }
    }
  }
  address_scopes? = { routed = { ip_version = 4, share_with? = [] } }
  subnet_pools?   = { tenants = { address_scope = "routed", prefixes = ["..."], default_prefixlen?, share_with? = [] } }

  security_groups? = { baseline-ssh = { description?, rules = {...}, share_with = ["demo"] } }

  dns_zones? = {
    demo     = { name = "demo.example.org.", email, ttl?, project = "demo" }        # created for the project
    services = { name = "svc.example.org.", email, ttl?, share_with = ["demo"] }    # kept by the operator, shared
  }

  existing? = { projects = {...}, users = {...}, groups = {...}, networks = { ext = { id? | name?, external?, share_with? } }, images = { golden = { id? | name?, share_with?, accept? } } }  # D4
}
```

- **Sharing is always explicit.** Every `share_with` lists project keys; sharing with every project is written as such, never a default.
- **Only what is declared is managed.** A quota not given is not set; a volume type quota appears only when declared, so that the cloud's own entries cause no difference in the plan.
- **DNS zones are never transferred.** A zone for a project is created on its behalf (the provider's sudo header), so the stack keeps reading it while the project owns it; a zone used by several projects stays the operator's and is shared. `project` and `share_with` are mutually exclusive.
- **The roles a project needs depend on the cloud's policies.** Octavia's advanced RBAC, its default policy, requires `load-balancer_member` besides `member` to create load balancers; with Keystone's default roles, `member` is enough. The module assigns whatever roles are given; the examples show both.
- **An image shared with a project is accepted on the project's side**: without it, a `member` user does not see it. How the module accepts on behalf of the project is settled by the specification (open question).

### D4. Adoption and takeover

- **Adoption**: the `existing` section references objects managed elsewhere (by ID or name), which then receive quotas, roles, shares or zones. Users from LDAP or federation are only adopted.
- **Takeover**: bringing objects created by hand under the module's management uses `import` blocks, in a guide, not in the model.

### D5. Output contract

- The IDs and names of every created or adopted object, keyed like the input, with a fixed shape (absent fields are `null`).
- The shape matches the `existing` inputs of the tenant layer and the planes contract of the reference, so that a project's foundation is handed over by injection, without lookups.

### D6. Engineering rules, as in the tenant layer

- **One plan, no `-target`.** Keys come only from the input; on an empty cloud, `plan` succeeds in one pass, and the plan after `apply` is empty, on OpenTofu and Terraform.
- **Secrets:** user passwords only, in three modes (`generate`, `input`, `none`), every secret `sensitive`; write-only attributes as soon as the provider supports them. No backend, no provider configuration, no secret store dependency.
- **No site-specific default**; examples use documentation names and ranges.

### D7. Tests

- **Without a cloud:** `tofu test` with a mocked provider, for the model (keys, references, validations, sharing targets).
- **On a cloud with the `admin` role:** a disposable DevStack bench, rebuilt from this repository ([spec](../specs/devstack-test-bench.md)): apply, empty plan after apply, adoption, takeover, what a `member` user sees of every shared object, destroy without leftover. The reference deployed on the foundation needs Octavia on the bench, with `v0.2`.
- Never against a production cloud.

### D8. Repository and releases

- A separate repository, published on the Terraform and OpenTofu registries, with its own versions. Compatibility with the tenant layer is a documented contract (D5), tested in the reference.
- The content of the first release is set by its specification.

## Consequences

- terraform-openstack-tenant removes `cloud-baseline` from its roadmap and refers to this repository; its ADR-0001 D4 is refined by this ADR.
- The reference's `v0.7` (routed planes) relies on address scopes and subnet pools from this module, tested on the bench.
- Open questions for the specification: the order of the first releases; image acceptance on behalf of a project; Octavia flavors and availability zones (admin objects useful to the entry point); application credentials for the tenant stacks.
