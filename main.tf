resource "hetzner_server" "frontend" {
  # Server configuration
}

resource "docker_container" "frontend" {
  name  = "kerry-frontend"
  image = "${var.registry_url}/kerry-frontend:latest"
  # Container configuration
} 