output "ssh" {
  description = "SSH command to the bench host."
  value       = "ssh stack@${module.host.instances["devstack-bench"].ports["main"].floating_ip}"
}
