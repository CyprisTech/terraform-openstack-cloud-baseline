# Spec: the first releases

- **Status:** Proposed
- **Related:** [ADR-0001](../adr/0001-module-design.md) (design of the module); [the DevStack test bench](devstack-test-bench.md); [openstack-multitenant-reference](https://github.com/CyprisTech/openstack-multitenant-reference), which consumes the module

## Problem

ADR-0001 sets the scope of the module, not the order in which it is delivered, and leaves four questions open: how a shared image is accepted on behalf of a project, whether Octavia's admin objects belong here, who creates the credentials of the tenant stacks, and the order of the releases.

## Goal

A first release usable on its own: an operator lays the foundation of a landing zone's projects with it, and the reference runs on that foundation. Later releases add what the reference's later releases need.

## Design

### 1. Releases

| Release | Content | Why in this order |
|---|---|---|
| `v0.1` | Projects and quotas (compute, network, block storage); users, groups, memberships and role assignments, roles adopted by name; flavors, public or restricted; images and their sharing; external and shared networks with RBAC; address scopes and subnet pools, shared by RBAC, and subnets taken from a pool; host aggregates and availability zones; the catalogue of shared security groups; DNS zones for a project or shared; adoption (`existing`) and the takeover guide; the output contract | What the reference's current scenario needs from the operator, plus the objects of its routed planes (its `v0.6`) and of a cloud with several zones (its `v0.5`): small, and testable on the one-node bench |
| `v0.2` | Octavia flavors, flavor profiles and availability zones; load balancer and DNS quotas | Needs Octavia on the bench (its step 2); the load balancer topology (active/standby) is an Octavia flavor |

Merged into `v0.1` on 2026-11-14: address scopes, subnet pools and aggregates were planned for `v0.2` and `v0.3`; the code is small and the one-node bench tests them. What a routed plane does (a tenant reached without address translation, routes learned by BGP) is the reference's test, not the module's.

Each release is tested on the bench (design 5) before it is published.

### 2. Images shared with a project

Glance shows a `shared` image to a project only once the project has accepted it, and acceptance is an action of the project itself.

- **Public catalogue images** (`visibility = "public"`): nothing to accept. The default for the images every project uses.
- **Images restricted to some projects** (`visibility = "shared"`, `share_with`): the module adds the members; the acceptance is done on the project's side, with project credentials.
  - Option A: the tenant layer accepts the images it is given (an input of terraform-openstack-tenant).
  - Option B: the module accepts on behalf of the project, if Glance's policy lets an administrator change a member's status. **Works on OpenStack 2026.1** (bench, 2026-11-14): the module accepts by default (`accept = true`); `accept = false` leaves the acceptance to the project. To check again on each release the bench moves to.
- The output contract lists, per project, the images shared with it and whether they still need acceptance.

### 3. Octavia's admin objects

Flavors and flavor profiles (single or active/standby topology) and Octavia availability zones are created by the operator and used by the tenants by ID. They belong to the foundation, in `v0.2`. The roles `load-balancer_*` are adopted, as every role (ADR-0001, D2).

### 4. Credentials of the tenant stacks

An application credential belongs to the user who creates it: an administrator cannot create one for another user.

- The module creates, when asked, **one user per tenant stack** with the roles it needs on its project (`member`, `load-balancer_member` where Octavia's policy requires it), password in `generate` mode.
- The owner of the stack creates the application credential with that user, outside the module: the secret never goes through the foundation's state.
- The guide shows the sequence: baseline apply, password read once from the sensitive output, application credential created by the stack owner, password rotated or the user restricted to application credentials.

### 5. Tests, per release

| Release | On the bench |
|---|---|
| `v0.1` | apply on an empty bench, then an empty plan; adoption of objects created beforehand; takeover with `import` blocks; as a `member` user of each project: the shared networks, the shared security groups, the flavors and images, the shared zone and the project's own zone are visible, the quotas apply; destroy without leftover |
| `v0.1`, routing and placement | a member takes a subnet from a pool shared with its project, another project cannot; a range already allocated is refused; an aggregate forms a zone and an instance is placed in it |
| `v0.2` | a load balancer of each Octavia flavor, in the requested Octavia zone; the reference deployed on the foundation (gateway mode, VM tenants) and its isolation test |

Every release also has tests with a mocked provider for the model: keys, references between objects, validations, sharing targets.

## Dependencies and order

1. The bench, steps 0 and 1 ([spec](devstack-test-bench.md)).
2. `v0.1`: the model and its mocked tests, then the resources by domain (identity, projects and quotas, compute and images, networks, security groups, DNS), each with its checks on the bench, then the output contract and the guides.
3. Publication of `v0.1` on the registries; terraform-openstack-tenant refers to it.
4. `v0.2` with the bench's step 2 (Octavia). The routed planes (no address translation, BGP) are tested by the reference's `v0.6`, on the bench's step 3.

## Proposed decisions

- The release order above, driven by what the reference needs.
- Public catalogue images by default; restricted images accepted by the module on the project's behalf (option B, checked on the bench), or by the project (`accept = false`).
- Octavia's admin objects in scope (`v0.2`).
- One user per tenant stack, created by the module; application credentials created by their owner.

## Open questions

- **Quotas with unified limits** (Keystone): several services move their limits there. Does the provider manage them, and from which OpenStack release do the reference's services read them?
- **Domains**: the default domain only in `v0.1`; a project in another domain when a user asks for it.
- **Flavors' extra specs**: free key/value pairs, or a few typed ones (CPU policy, disk quality of service)?
