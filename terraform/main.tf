# Create SSH key
resource "hcloud_ssh_key" "default" {
  name       = "kerry-ssh-key"
  public_key = var.ssh_public_key
}

# Create a basic firewall
resource "hcloud_firewall" "default" {
  name = "kerry-firewall"

  # SSH access - Consider restricting to specific IPs
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",  # TODO: Restrict to specific IP ranges
      "::/0"
    ]
  }

  # HTTP/HTTPS access - Using local variable for Cloudflare IPs
  dynamic "rule" {
    for_each = toset(["80", "443"])
    content {
      direction = "in"
      protocol  = "tcp"
      port      = rule.value
      source_ips = [
        # IPv4 ranges
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        # IPv6 ranges
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32"
      ]
    }
  }
}

# Create server
resource "hcloud_server" "main" {
  name        = var.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.server_location

  ssh_keys = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.default.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    environment = var.environment
    managed_by = "terraform"
  }

  user_data = <<-EOF
#!/bin/bash
set -ex
exec 1> >(tee -a /var/log/user-data.log) 2>&1

echo "[$(date)] Starting server setup..."

# Install Docker and Docker Compose
${file("${path.module}/files/docker-install.sh")}

# Create app directory
mkdir -p /opt/kerry

# Create docker-compose file
cat > /opt/kerry/docker-compose.yml << 'DOCKEREOF'
${templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    database_url = var.database_url,
    redis_url = var.redis_url
})}
DOCKEREOF

# Pull the latest frontend image (with error handling)
echo "[$(date)] Attempting to pull frontend image..."
if docker pull ${var.registry_url}/-staging:latest; then
    echo "[$(date)] Successfully pulled frontend image"
    
    # Create and start the frontend container
    docker run -d \
      --name kerry-frontend-staging \
      -p 3000:80 \
      --restart always \
      ${var.registry_url}/kerry-frontend-staging:latest
else
    echo "[$(date)] Warning: Failed to pull frontend image. Continuing with setup..."
fi

# Install nginx
echo "[$(date)] Installing nginx..."
apt-get update
apt-get install -y nginx

# Create error page
cat > /var/www/html/error.html << 'HTMLEOF'
${file("${path.module}/files/error.html")}
HTMLEOF

# Configure nginx
${templatefile("${path.module}/files/configure-nginx.sh", {
  cloudflare_cert = var.cloudflare_cert,
  cloudflare_key = var.cloudflare_key,
  login_html = templatefile("${path.module}/files/login.html", {
    staging_username = var.staging_username,
    staging_password = var.staging_password,
    auth_token = base64encode("${var.staging_username}:${var.staging_password}")
  })
})}

echo "[$(date)] Setup completed successfully!"
EOF
}
