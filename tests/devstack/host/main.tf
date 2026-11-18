# The bench host: one instance, its network, a router and a floating IP for
# SSH. Everything the tests create lives inside this instance; the hosting
# cloud only sees it. The member role on the hosting project is enough.

module "cloudinit" {
  source  = "CyprisTech/tenant/openstack//modules/cloudinit"
  version = "0.1.5"

  hostname = "devstack-bench"
  users = {
    stack = {
      ssh_authorized_keys = [var.ssh_public_key]
      sudo                = true
    }
  }
  packages = ["git", "python3-venv", "bridge-utils", "frr"]
}

module "host" {
  source  = "CyprisTech/tenant/openstack"
  version = "0.1.5"

  tenant = {
    existing = {
      networks = merge(
        { ext = { name = var.external_network } },
        var.egress_network == null ? {} : { egress = { name = var.egress_network } },
      )
    }

    networks = {
      devstack-net = {
        mtu     = var.network_mtu
        subnets = { main = { cidr = var.cidr, dns_nameservers = var.dns_nameservers } }
        # The default route goes out through the egress network when one is given; the SSH
        # sources are then reached back through the router of the floating IP.
        routers = {
          for k, r in {
            devstack-router = {
              external_network = "ext", internal_subnet = "main",
              default_gateway  = var.egress_network == null
              advertise_routes = var.egress_network == null ? [] : var.ssh_sources
            }
            devstack-egress = { external_network = "egress", internal_subnet = "main", default_gateway = true, advertise_routes = [] }
          } : k => r if k == "devstack-router" || var.egress_network != null
        }
      }
    }

    security_groups = {
      devstack-ssh = {
        description = "SSH to the DevStack bench host"
        rules = {
          for i, cidr in var.ssh_sources : "ssh-${i}" => {
            direction = "ingress", protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = cidr
          }
        }
      }
    }

    instances = {
      devstack-bench = {
        az        = var.az
        flavor    = var.flavor
        image     = var.image
        user_data = module.cloudinit.rendered
        labels    = ["devstack-bench"]
        ports = {
          main = {
            network         = "devstack-net"
            subnet          = "main"
            security_groups = ["devstack-ssh"]
            floating_ip     = { pool = "ext" }
          }
        }
      }
    }
  }
}
