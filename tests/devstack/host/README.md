# DevStack bench host

Creates the virtual machine that hosts the DevStack test bench ([spec](../../../docs/specs/devstack-test-bench.md)), with [terraform-openstack-tenant](https://github.com/CyprisTech/terraform-openstack-tenant): a network, a router, a security group that opens SSH to the given sources only, the instance and a floating IP. The `member` role on the hosting project is enough.

Everything the tests create (DevStack's services, the test instances, the amphorae) lives inside this instance.

## Requirements

- A flavor with 8 vCPUs, 32 GB of RAM and a 100 GB local disk.
- Nested virtualization on the compute nodes (`/sys/module/kvm_amd/parameters/nested` or `kvm_intel` set to `1`), so that the bench runs its instances with KVM.
- An Ubuntu 24.04 cloud image.

## Networks

The floating IP for SSH is taken from `external_network`, and only the given `ssh_sources` may connect. When that network gives no Internet access, set `egress_network`: a second router takes the default route (package mirrors, git, DevStack's downloads), and the SSH sources are routed back through the first one. The DNS resolvers must then be reachable through the egress network.

## Usage

```bash
cp env.tfvars.example env.tfvars   # git-ignored; adapt to the hosting cloud
tofu init
tofu apply -var-file=env.tfvars
tofu output -raw ssh
```

The host may stay up between test sessions. Destroy it when its capacity is needed elsewhere:

```bash
tofu destroy -var-file=env.tfvars
```

## Snapshot (optional)

The bench is rebuilt by script (`tofu apply`, then `install.sh`): nothing requires a snapshot. Where the hosting cloud's image store has room for it (the used size of the disk, 15 to 40 GB), `snapshot.sh <step>` stops the host, snapshots it as a private image of the hosting project, starts it again and deletes the previous snapshot of the same step. To restart from a snapshot, set `image` to its name in `env.tfvars` and apply.
