# DevStack test bench

A disposable OpenStack cloud on one virtual machine, where the tests hold the `admin` role, with operator planes simulated inside the machine ([spec](../../docs/specs/devstack-test-bench.md)).

| File | Role |
|---|---|
| [host/](host/) | Creates the bench host on any OpenStack cloud, with the `member` role |
| [local.conf.tmpl](local.conf.tmpl) | DevStack configuration: `stable/2026.1`, OVN, Cinder, Designate; no network created by DevStack; one physical network per plane |
| [planes.sh](planes.sh) | The simulated planes: one bridge per plane, a namespace behind each, egress through the host |
| [install.sh](install.sh) | Builds the bench on the host, as the user `stack`: the tools of the checks (OpenTofu, pinned and checksum verified; jq; bc), the planes, DevStack |
| [check-all.sh](check-all.sh) | Runs every check, step 0 first, and prints a summary |
| [check-step0.sh](check-step0.sh) | Exit criterion of step 0, run after install.sh and after a reboot: planes and OVN mappings up; a member user's instance reaches the four planes, resolves names and a package mirror; a floating IP reachable from `ns-internet`; a volume attached; a DNS record active. Cleans up before and after |

## Planes

| Physical network | Bridge | Namespace | Range | Plays |
|---|---|---|---|---|
| `internet` | `br-internet` | `ns-internet` | 203.0.113.0/24 | the Internet: a client, and egress through the host |
| `intranet` | `br-intranet` | `ns-onprem` | 192.0.2.0/24 | an on-premises network |
| `publication` | `br-publication` | `ns-consumer` | 198.51.100.0/24 | a consumer of published services |
| `routed` | `br-routed` | `ns-operator` | 100.64.0.0/24 | the operator's router of a routed plane |

In each namespace, the first address of the range is the operator's side of the plane and the second one a client. A check runs in a namespace, for example `sudo ip netns exec ns-onprem curl -k https://...`.

## Build

1. **The host**, from a machine with credentials for the hosting project (see [host/](host/README.md)):

   ```bash
   cd tests/devstack/host
   cp env.tfvars.example env.tfvars          # adapt: networks, MTU, resolvers, flavor, SSH sources and key
   tofu init && tofu apply -var-file=env.tfvars
   tofu output -raw ssh                      # ssh stack@<address>
   ```

2. **A copy of the repository on the host.** The host needs no access to your git server: copy the working tree (or clone the public repository once published).

   ```bash
   rsync -a --exclude .git --exclude '.terraform*' --exclude '*.tfstate*' --exclude tests/devstack/host \
     ./ stack@<address>:cloud-baseline/
   ```

3. **The bench**, on the host:

   ```bash
   cd cloud-baseline/tests/devstack
   ./install.sh                              # 30 to 60 minutes
   ```

   If `stack.sh` fails (a download that timed out, for example), run `./install.sh` again: it resumes. If it fails the same way twice, rebuild the host rather than repairing it.

## Checks

On the host, after `install.sh`:

```bash
./check-all.sh                            # every check, step 0 first, with a summary
./check-all.sh step0 networks             # or some of them
```

| Check | What it proves |
|---|---|
| `step0` | the bench itself: planes, OVN mappings, a member's instance on the four planes, DNS, mirror, floating IP, volume, DNS record |
| `identity`, `compute`, `networks`, `security`, `dns` | each domain of the module on the bench: apply, empty plan after apply, what a member user sees and cannot do, destroy without leftover |
| `takeover` | objects created with the CLI taken over with `import` blocks: nothing created, changed or destroyed |

**After a reboot of the host**, run `./check-all.sh step0`: the planes and their OVN mappings come back at boot (unit `devstack-planes`), DevStack's services too.

To work by hand on the bench: `source /opt/stack/devstack/openrc admin admin` (or `demo demo` for a member user); the simulated outside of each plane is reached with `sudo ip netns exec <namespace> ...`.

The bench is never repaired by hand nor upgraded: rebuild it, or restart from a snapshot ([host/](host/README.md#snapshot-optional)).
