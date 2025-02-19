# Create SSH key
resource "hcloud_ssh_key" "default" {
  name       = "kerry-ssh-key"
  public_key = var.ssh_public_key
}

# Create a basic firewall
resource "hcloud_firewall" "default" {
  name = "kerry-firewall"

  # SSH access - Temporarily open to all
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # HTTP access - Open to all
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # HTTPS access - Open to all
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
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
    environment = "general"
  }

  user_data = <<-EOF
#!/bin/bash

# Enable logging and exit on error
set -ex
exec 1> >(tee -a /var/log/user-data.log) 2>&1

echo "[$(date)] Starting server setup..."

# Direct package installation without waiting
echo "[$(date)] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx apache2-utils

# Verify Nginx installation
if ! command -v nginx >/dev/null 2>&1; then
    echo "[$(date)] ERROR: Nginx installation failed!"
    exit 1
fi

echo "[$(date)] Nginx installed successfully"

# Create SSL directory
echo "[$(date)] Setting up SSL..."
mkdir -p /etc/nginx/ssl

# Configure SSL certificates
echo "[$(date)] Configuring SSL certificates..."
echo "${var.cloudflare_cert}" > /etc/nginx/ssl/cloudflare.crt
echo "${var.cloudflare_key}" > /etc/nginx/ssl/cloudflare.key
chmod 600 /etc/nginx/ssl/cloudflare.key

# Configure Nginx
echo "[$(date)] Configuring Nginx..."
cat > /etc/nginx/sites-available/default << 'EOL'
server {
    listen 80;
    listen 443 ssl;
    server_name staging.kerryai.app;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # SSL protocols and ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;

    auth_basic "Kerry AI Staging";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        return 200 'Kerry AI Staging - Coming Soon!';
        add_header Content-Type text/plain;
    }
}
EOL

# Setup auth
echo "[$(date)] Setting up authentication..."
htpasswd -bc /etc/nginx/.htpasswd ${var.staging_username} ${var.staging_password}

# Start Nginx
echo "[$(date)] Starting Nginx..."
systemctl enable nginx
systemctl restart nginx

# Verify Nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "[$(date)] ERROR: Nginx failed to start!"
    exit 1
fi

echo "[$(date)] Setup complete successfully!"
EOF
}