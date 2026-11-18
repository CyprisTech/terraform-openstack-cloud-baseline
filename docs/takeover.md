# Taking over an existing cloud

An administrator rarely starts from an empty cloud. Two ways to work with what exists:

| | Adoption | Takeover |
|---|---|---|
| What | The module references an object that stays managed elsewhere | The module manages an object created by hand or by another tool |
| How | `existing` in the model, by ID or name | `import` blocks, then the object is described in the model like any other |
| Objects | projects, users (LDAP, federation), groups, networks (the deployment tool), images (a pipeline) | everything the module creates |
| On `destroy` | the object stays | the object is deleted |

Adopt what someone else owns (users from a directory, projects of another team); take over what this configuration should own from now on.

## Procedure

1. **Describe the objects in the model as they are**: same names, same ranges, same rules, same sharing. The module names objects after their keys: a subnet is `<network>-<subnet key>`.
2. **Add one `import` block per object**, in the root configuration that calls the module (here, a module called `baseline`).
3. **Read the plan before applying.** It must import every object and create or destroy nothing. A creation or a replacement means the model does not match the object: correct the model, not the object.
4. **Apply, then plan again**: the plan must be empty. The `import` blocks can then be removed.

## Addresses and import IDs

| Object | Address | Import ID |
|---|---|---|
| project | `module.baseline.openstack_identity_project_v3.this["<project>"]` | project ID |
| compute, network, volume quotas | `module.baseline.openstack_compute_quotaset_v2.this["<project>"]`, `openstack_networking_quota_v2`, `openstack_blockstorage_quotaset_v3` | `<project ID>/<region>` |
| user | `module.baseline.openstack_identity_user_v3.this["<user>"]` | user ID |
| group | `module.baseline.openstack_identity_group_v3.this["<group>"]` | group ID |
| membership | `module.baseline.openstack_identity_user_membership_v3.this["<group>/<user>"]` | `<user ID>/<group ID>` |
| role assignment | `module.baseline.openstack_identity_role_assignment_v3.this["<assignment>"]` | `<domain ID>/<project ID>/<group ID>/<user ID>/<role ID>`, empty where absent: `/<project ID>/<group ID>//<role ID>` for a group |
| flavor | `module.baseline.openstack_compute_flavor_v2.this["<flavor>"]` | flavor ID |
| flavor access | `module.baseline.openstack_compute_flavor_access_v2.this["<flavor>/<project>"]` | `<flavor ID>/<project ID>` |
| image (not tested on the bench yet) | `module.baseline.openstack_images_image_v2.this["<image>"]` | image ID |
| image member (not tested yet) | `module.baseline.openstack_images_image_access_v2.this["<image>/<project>"]` | `<image ID>/<project ID>` |
| network | `module.baseline.openstack_networking_network_v2.this["<network>"]` | network ID |
| subnet | `module.baseline.openstack_networking_subnet_v2.this["<network>/<subnet>"]` | subnet ID |
| host route | `module.baseline.openstack_networking_subnet_route_v2.this["<network>/<subnet>/<destination>"]` | `<subnet ID>-route-<destination>-<next hop>` |
| network sharing | `module.baseline.openstack_networking_rbac_policy_v2.network["<network>/<project or *>"]` | RBAC policy ID |
| address scope | `module.baseline.openstack_networking_addressscope_v2.this["<scope>"]` | address scope ID |
| subnet pool | `module.baseline.openstack_networking_subnetpool_v2.this["<pool>"]` | subnet pool ID |
| scope and pool sharing | `module.baseline.openstack_networking_rbac_policy_v2.address_scope["<scope>/<project or *>"]`, `openstack_networking_rbac_policy_v2.subnet_pool["<pool>/<project or *>"]` | RBAC policy ID |
| aggregate | `module.baseline.openstack_compute_aggregate_v2.this["<aggregate>"]` | aggregate ID |
| security group | `module.baseline.openstack_networking_secgroup_v2.this["<group>"]` | group ID |
| security group rule | `module.baseline.openstack_networking_secgroup_rule_v2.this["<group>/<rule>"]` | rule ID |
| security group sharing | `module.baseline.openstack_networking_rbac_policy_v2.security_group["<group>/<project or *>"]` | RBAC policy ID |
| DNS zone | `module.baseline.openstack_dns_zone_v2.this["<zone>"]` | zone ID; `<zone ID>:<project ID>` for a zone owned by a project (a colon: the provider's documentation shows a slash, its code splits on a colon) |
| DNS zone share (not tested yet) | `module.baseline.openstack_dns_zone_share_v2.this["<zone>/<project>"]` | `<zone ID>/<share ID>` |

```hcl
import {
  to = module.baseline.openstack_identity_project_v3.this["web"]
  id = "6b1f..."
}
```

## What to watch

| Object | What to do |
|---|---|
| A user | `password = { mode = "none" }`: the module then leaves the user's password as it is. A generated password would replace it. |
| A security group created by hand | Neutron added its default egress rules: set `delete_default_rules = false`, or declare those rules in the model to manage them. |
| An external network made external by hand | Neutron created an RBAC policy for every project (`access_as_external`, target `*`): import it as the network's sharing with `*`. |
| A shared network | Each RBAC policy is an object: one `import` block per project it is shared with. |
| Quotas | Only the quotas declared are managed; the others keep their current values. |
| A DNS zone owned by a project | Import it with `<zone ID>:<project ID>`, or the administrator cannot read it. |

## At scale

A cloud with hundreds of projects and thousands of objects is not taken over with one `import` block each:

1. **One configuration per group of objects** (a set of projects, the flavors and images, the shared networks), taken over one after the other: states stay small and a mistake stays in one group.
2. **Generate the inventory from the API** (`openstack project list -f json`, `openstack flavor list --all -f json`…) and turn it into the model, keyed by name, and into the IDs to import, keyed the same way.
3. **One `import` block per kind of object**, with `for_each` over the generated list (OpenTofu and Terraform 1.7 and later):

   ```hcl
   import {
     for_each = var.existing_projects # generated: "<project>" => "<project ID>"
     to       = module.baseline.openstack_identity_project_v3.this[each.key]
     id       = each.value
   }
   ```

   The model declares the same keys (`baseline.projects`), generated from the same list.
4. **Read the plan**: every object imported, nothing created or destroyed. A mismatch is corrected in the generator, not in the cloud.

The same method, with a list generated from the API and `for_each`, is tested on a real cloud by stage [`06-takeover`](https://github.com/CyprisTech/terraform-openstack-tenant/tree/main/tests/integration/06-takeover) of terraform-openstack-tenant; the bench of this repository takes over objects one block each.

## Tested

`tests/devstack/check-takeover.sh` creates with the CLI a project and its quota, a user, a group and its membership, a role assignment, a flavor, an internal network shared with a project, an external network made external for every project, a security group shared with a project and a DNS zone owned by a project, then takes them over: the plan imports the 17 objects and creates, changes or destroys nothing; the plan after apply is empty ([DevStack bench](specs/devstack-test-bench.md)).
