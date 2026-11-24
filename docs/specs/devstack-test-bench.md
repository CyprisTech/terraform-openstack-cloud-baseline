# Spec: a DevStack test bench

- **Status:** Proposed
- **Related:** the `cloud-baseline` module design (ADR-0001, to be written); [openstack-multitenant-reference](https://github.com/CyprisTech/openstack-multitenant-reference), whose `v0.7` (routed operator planes and operator segments) needs the same bench

## Problem

`cloud-baseline` creates objects that need the `admin` role: projects, quotas, users, role assignments, aggregates, flavors, images, provider networks, address scopes, subnet pools, shared security groups and DNS zones. Its tests cannot run in a project with the `member` role, and they must not run against a production cloud: a wrong plan there changes every tenant at once.

The reference has the same need for its routed operator planes and the segments an operator gives each project (`v0.7`): address scopes, subnet pools and an operator router that holds routes to the tenant prefixes, and provider segments behind an operator gateway, tested on a cloud whose operator planes we control. Its availability zones (`v0.5`) need no bench: the reference tests their placement with mocked providers ([ADR-0011](https://github.com/CyprisTech/openstack-multitenant-reference/blob/main/docs/adr/0011-resilience-scope.md) of the reference).

## Goal

A test bench that anyone can rebuild from this repository:

- a disposable OpenStack cloud on one virtual machine, where the tests hold the `admin` role;
- operator planes simulated inside the machine, with their outside (the Internet, an on-premises network, an operator router) played by network namespaces, so nothing leaves the bench;
- the module's tests: apply, an empty plan after apply, adoption, takeover with `import` blocks, what a `member` user sees of shared objects, destroy without leftover;
- the reference deployed on top in gateway mode, with VM tenants, and its isolation test.

Out of scope:

- **Kubernetes tenants** and the shared cluster: too heavy for nested virtualization. They stay tested on a full cloud.
- **The interface mode of the reference**: it needs no `admin` role and stays tested on a full cloud.
- **Performance and scale**: the bench proves behaviour, not capacity.
- **A CI job**: the bench is too large for hosted runners. It is run by the maintainers before a release, like the reference's campaign.

## Design

### 1. Host

- One virtual machine on any OpenStack cloud: Ubuntu 24.04, 8 vCPUs, 32 GB of RAM, a 100 GB local root disk (an ephemeral Nova disk is faster than a volume, and the bench is disposable).
- The machine is created by the configuration `tests/devstack/host/`, which uses [terraform-openstack-tenant](https://github.com/CyprisTech/terraform-openstack-tenant): its network, a router, a floating IP for SSH and the instance. It works with the `member` role, so the bench can be hosted in any project.
- Everything the tests create (DevStack's services, the instances, the amphorae) lives inside this machine: the hosting cloud only sees one instance. DevStack's services take about 8 to 10 GB of RAM; the rest is left to the test instances, which use small flavors.
- **Nested virtualization** on the hosting compute node (`/dev/kvm` present in the machine), with `LIBVIRT_TYPE=kvm` and `LIBVIRT_CPU_MODE=host-passthrough`. Without it, instances run under plain QEMU: enough for steps 0 and 1, too slow for Octavia amphorae.
- The tests run **on the bench itself** (OpenTofu installed there, `clouds.yaml` written by DevStack). The bench's APIs are never exposed; the maintainer drives it over SSH.

### 2. DevStack

- `stable/2026.1` for DevStack and every project: a maintained SLURP release, so that a broken development branch never blocks a run. `2025.1` is unmaintained and has no stable branch any more; the reference is already tested on a `2025.1` cloud, so the bench adds a second release.
- Services: Keystone, Glance, Nova, Placement, Neutron with OVN, Cinder (LVM), Designate (its DevStack plugin, BIND backend). Octavia from step 2. No Horizon, Swift or Tempest.
- `NEUTRON_CREATE_INITIAL_NETWORKS=False`: DevStack creates no network. The provider networks are created by `cloud-baseline`, since that is what is tested.
- `OVN_BRIDGE_MAPPINGS` maps one physical network per plane to one Open vSwitch bridge (design 3).
- The `local.conf` is a template in `tests/devstack/`, with no address or name of any real cloud.

### 3. Simulated operator planes

| Physical network | Bridge | Role in the tests | Outside, played by |
|---|---|---|---|
| `internet` | `br-internet` | Internet egress and public entry | namespace `ns-internet`: a client, and egress to the host's uplink by NAT so that instances reach package mirrors |
| `intranet` | `br-intranet` | an operator plane towards on-premises networks | namespace `ns-onprem`: a client and a small HTTP service |
| `publication` | `br-publication` | the plane on which services are published | namespace `ns-consumer`: a client |
| `routed` | `br-routed` | a routed operator plane, without NAT (step 3) | namespace `ns-operator`: an FRR router, also attached to `ns-onprem` |
| `segments` (VLAN) | `br-segments` | one segment per project, behind the operator's gateway (step 3) | namespace `ns-gateway`: the operator's gateway, one VLAN interface per segment, routing and filtering between the segments and towards the other planes' namespaces |

- A script `tests/devstack/planes.sh up|down|status` creates the bridges, the veth pairs and the namespaces, with fixed documentation prefixes (RFC 5737 and RFC 1918 ranges chosen for the bench). It is idempotent.
- Bridges persist across reboots; namespaces do not. A oneshot systemd unit runs `planes.sh up` at boot.
- Each check in the tests is a command run in a namespace (`ip netns exec ns-onprem curl ...`), the same way the reference's isolation test runs its probes.

### 4. Test scenarios

1. **The module alone.**
   - Apply the module's test configuration, then check that a second plan is empty.
   - Adopt objects created beforehand by a script (`existing` section).
   - Take over hand-made objects with `import` blocks.
   - Log in as a `member` user and check what is visible: networks shared by RBAC, the shared security groups, an accepted image, a shared DNS zone, a zone created for the project.
   - Destroy, then check that nothing is left.
2. **The reference in gateway mode.** The operator planes produced by the module are the reference's inputs. Deploy the shared stacks, the entry point, the `vm` tenants (public, and private: no exposure, no egress), then run `check.py`, without the lines that involve Kubernetes.
3. **Routed planes and segments.**
   - The module creates an address scope and a subnet pool on the `routed` plane; a tenant router reaches it without SNAT. The target is a plane routed by BGP: the operator learns the tenant prefixes from Neutron's BGP speaker. On the bench, `ns-operator` holds the same routes statically, in place of the BGP session: the routed behaviour is tested (no translation, prefixes from the scope, reachability from `ns-onprem`), the BGP session itself is not (decided on 2026-11-19); the module's BGP speaker and peers are covered by mocked tests.
   - The module creates one provider segment (VLAN) per project, owned by the operator and shared with that project only by RBAC; the reference's tenants adopt them with no router (the reference's spec of operator segments).
   - New isolation lines: a tenant reachable from `ns-onprem` without NAT; a prefix overlapping another scope refused; no path between two scopes; no path from a segment to another project's segment other than through `ns-gateway`.

### 5. Rebuild and snapshot

- The bench is rebuilt by script: `tofu apply` of the host, then `install.sh` (30 to 60 minutes for `stack.sh`). It may stay up between sessions; it is destroyed when its capacity is needed elsewhere.
- A snapshot is optional: where the hosting cloud's image store has room for it (the used size of the disk), `host/snapshot.sh` keeps one per step, and a session restarts from it.
- The bench is never upgraded. A new OpenStack release means a new bench, built from an updated template.

## Dependencies and order

Each step is delivered and tested on its own, with an exit criterion and a fallback.

| Step | Content | Exit criterion | Fallback |
|---|---|---|---|
| 0 | One node, OVN, Designate; planes simulated | `install.sh` succeeds from scratch; a `member` user boots an instance that reaches `ns-internet` and `ns-onprem` through networks created by hand | none: this is the base |
| 1 | Scenario 1 | all checks pass, then destroy without leftover | none |
| 2 | Octavia, scenario 2 | a load balancer active in under 5 minutes; `check.py` passes | without nested virtualization, the entry point stays tested on a full cloud |
| 3 | Scenario 3 | routed planes (static routes in place of BGP) and segments, with the new isolation lines | none |

Steps 0 and 1 serve `cloud-baseline` `v0.1`. Step 3 serves the reference's `v0.7`.

## Proposed decisions

- **DevStack, not an all-in-one deployment of Kolla-Ansible or OpenStack-Ansible.** DevStack is the tool of OpenStack's own CI: one configuration file, one script, documented plugins for Designate and Octavia. The all-in-one deployments are closer to production and much heavier to build and to debug. The bench proves the behaviour of the APIs, which is the same.
- **Planes simulated in namespaces on the bench**, not networks of the hosting cloud. The bench is self-contained, the tests cannot touch the hosting cloud's networks, and anyone can rebuild it.
- **The tests run on the bench**, so its APIs are never exposed.
- **One pinned stable branch**, a maintained SLURP release, other than the one of the full cloud the reference is tested on.
- **A disposable bench**: rebuilt by script (or restored from an optional snapshot), never repaired by hand, never upgraded.
- **One node.** Availability zones are not tested on the bench; the reference tests their placement with mocked providers.
- **The bench lives in this repository** (`tests/devstack/`); the reference links to it for its `v0.7` tests.

## Open questions

- **Package mirrors**: instances reach the Internet through the host's NAT. A local cache (an apt proxy) would protect the runs from a slow or failing mirror.

## Settled

- **Nested virtualization**: enabled on the hosting cloud's compute nodes (2026-11-13); `install.sh` warns when `/dev/kvm` is missing, to check again at the first run of step 2.
- **The Octavia amphora image**: built by DevStack at each `stack.sh`, like the bench itself, which is rebuilt rather than stored. An image built for another OpenStack release (that of the hosting cloud) is not reused: the amphora agent follows the controller's release.
- **BGP**: the routed planes target BGP; on the bench, static routes on the operator's side stand in for the routes BGP would advertise. The routed behaviour is tested, the BGP session is documented, not tested.
