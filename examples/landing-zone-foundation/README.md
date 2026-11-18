# Example: the foundation of a small landing zone

A project for shared services and one per tenant, with their quotas; groups and their roles (`member`, and `load-balancer_member` where Octavia's policy requires it), the users adopted from the directory; two flavors and an image; an external network for every project and an intranet network for two of them; a shared security group; a DNS zone owned by each tenant.

```bash
export OS_CLOUD=my-cloud-admin   # admin credentials
tofu init && tofu apply
```

The outputs `networks`, `security_groups` and `dns_zones` have the shape of the `existing` input of [terraform-openstack-tenant](https://github.com/CyprisTech/terraform-openstack-tenant): each tenant adopts them with its own `member` credentials.

The physical network names (`public`, `intranet`) and the address ranges are those of your cloud; the ones here are examples.
