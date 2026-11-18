terraform {
  required_version = ">= 1.9"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.2"
    }
  }
}

# Credentials come from clouds.yaml (OS_CLOUD). Unset every other OS_* variable
# so that the client does not mix them with the cloud entry.
provider "openstack" {}
