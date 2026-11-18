# Testing

| Level | What | Where |
|---|---|---|
| Mocked | the model: keys, references between objects, validations, sharing targets; no cloud | `tests/*.tftest.hcl`, CI on OpenTofu and Terraform (lowest supported and latest) |
| Bench | each domain on a real OpenStack cloud with the `admin` role: apply, empty plan after apply, what a `member` user sees and cannot do, destroy without leftover | the disposable [DevStack bench](../tests/devstack/README.md), `check-all.sh` |

The bench is rebuilt from the repository: the host by `tests/devstack/host`, DevStack and the simulated planes by `install.sh`. Nothing is done by hand.

## Results

### 2026-11-14 — before v0.1.0

DevStack `stable/2026.1` (OVN, Cinder, Designate), Ubuntu 24.04, one node; OpenTofu 1.13.2, provider 3.4.0. The bench was rebuilt from scratch from `main` (host recreated, empty plan after apply, `install.sh` in 9 minutes), then:

| Check | What it proves | Result |
|---|---|---|
| `step0` | the bench: planes and OVN mappings, a member's instance on the four planes, DNS, mirror, floating IP, volume, DNS record; also after a reboot of the host | 11/11 (a run failed once: Keystone restarted by an automatic upgrade, fixed below) |
| `identity` | projects and quotas (given ones set, others left to the cloud), generated password, roles through a group on a created and an adopted project, adopted objects kept on destroy | 10/10 |
| `compute` | restricted flavor visible in its project only; shared image accepted on the project's behalf, unaccepted image not listed; adopted image shared and kept on destroy | 11/11 |
| `networks` | external network shared with every project or with one; internal network shared with one; host route, MTU; adopted network shared and kept on destroy | 15/15 |
| `routing` | subnet from a shared pool, refused to another project; allocated range refused; aggregate forming a zone, instance placed in it | 10/10 |
| `security` | shared group attached by the projects it is shared with only; no rule added by a project; only the rules given | 8/8 |
| `dns` | zone created for a project owned by it; shared zone written by the projects it is shared with only | 9/9 |
| `takeover` | 17 objects created with the CLI imported: nothing created, changed or destroyed; empty plan after apply | 4/4 |

Mocked: 20 runs pass on OpenTofu and Terraform.

## Defects found by the bench

Mocked tests could not show them; each is fixed and covered by a check.

| Defect | Fix |
|---|---|
| The provider refuses `no_gateway = false` next to `gateway_ip` | `no_gateway` passed only when true |
| Neutron reports a network external as soon as one `access_as_external` policy exists | sharing always through RBAC policies, the network's own attributes ignored |
| A tracker of the sharing mode replaced the networks on takeover | removed: going from every project to a list is an in-place change of policies |
| Neutron shares a subnet pool with a project only once the project has access to the pool's address scope | the pool's policies wait for the scope's; a validation refuses a pool shared wider than its scope |
| The provider's documentation shows `zone_id/project_id` to import a zone owned by a project; its code expects `zone_id:project_id` | documented in the [takeover guide](takeover.md) |
| The network data source takes `external` as a filter and does not return it | `external` declared for an adopted network |
| Ubuntu's automatic upgrades restarted Apache, hence Keystone, during a run of the checks | disabled by `install.sh`: the bench is never upgraded |

Not tested on the bench yet: quotas per volume type, the takeover of images, image members and zone shares (their import IDs are documented), Octavia objects (`v0.2`).
