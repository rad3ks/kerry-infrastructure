output "server_ip" {
  description = "Public IP address of the server"
  value       = hcloud_server.main.ipv4_address
}

output "server_status" {
  description = "Status of the server"
  value       = hcloud_server.main.status
}

output "frontend_url" {
  description = "URL where frontend is accessible"
  value       = "https://${var.server_name}"
}

output "registry_url" {
  description = "Container registry URL for frontend deployments"
  value       = var.registry_url
  sensitive   = true
}
