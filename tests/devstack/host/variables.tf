variable "external_network" {
  description = "External network of the hosting cloud carrying the floating IP for SSH."
  type        = string
}

variable "egress_network" {
  description = "External network giving the default route (package mirrors, git), when it is not external_network. The bench host gets no address on it."
  type        = string
  default     = null
}

variable "az" {
  description = "Availability zone of the bench host."
  type        = string
}

variable "image" {
  description = "Ubuntu 24.04 cloud image of the hosting cloud."
  type        = string
}

variable "flavor" {
  description = "Flavor of the bench host: 8 vCPUs, 32 GB of RAM, 100 GB local disk."
  type        = string
}

variable "cidr" {
  description = "Address range of the bench host's network. It must not overlap the ranges simulated inside the bench."
  type        = string
  default     = "192.168.240.0/28"
}

variable "network_mtu" {
  description = "MTU of the bench host's network; null keeps the cloud's default. Set it when the cloud's tenant networks need a smaller MTU than Neutron's default, or large transfers stall."
  type        = number
  default     = null
}

variable "dns_nameservers" {
  description = "DNS resolvers pushed by DHCP to the bench host's network, reachable through the default route (the egress network when one is given)."
  type        = list(string)
  default     = []
}

variable "ssh_sources" {
  description = "Address ranges allowed to reach the bench host over SSH. The bench's APIs are never opened."
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Public key of the user `stack`, which runs DevStack and the tests."
  type        = string
}
