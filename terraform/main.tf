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

# Enable logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

echo "[$(date)] Starting server setup..."

# Wait for cloud-init and apt
echo "[$(date)] Waiting for cloud-init..."
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do 
    sleep 1
done

# Wait for apt locks
echo "[$(date)] Waiting for apt locks..."
while lsof /var/lib/apt/lists/lock >/dev/null 2>&1 || lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 1
done

# Install packages
echo "[$(date)] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx apache2-utils

# Create SSL directory
echo "[$(date)] Setting up SSL..."
mkdir -p /etc/nginx/ssl

# Configure SSL certificates
cat > /etc/nginx/ssl/cloudflare.crt << 'CERT'
${var.cloudflare_cert}
CERT

cat > /etc/nginx/ssl/cloudflare.key << 'KEY'
${var.cloudflare_key}
KEY

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

echo "[$(date)] Setup complete!"
EOF
}