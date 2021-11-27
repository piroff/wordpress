output "private_key" {
  value       = tls_private_key.ssh.private_key_pem
  description = "SSH private key"
  sensitive   = true
}

output "db_pass" {
  value     = module.db_default.db_pass
  sensitive = true
}

output "instance_id" {
  value = module.ec2_complete[*].id
}

output "instance_public_ip" {
  value = module.ec2_complete[*].public_ip
}

output "lb_dns_name" {
  value = module.alb.lb_dns_name
}
