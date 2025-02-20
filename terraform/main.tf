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

  # HTTP access - Cloudflare IPs only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
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

  # HTTPS access - Cloudflare IPs only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
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

# Install required packages
echo "[$(date)] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx apache2-utils

# Verify installation
if ! command -v nginx >/dev/null 2>&1; then
    echo "[$(date)] ERROR: Nginx installation failed!"
    exit 1
fi

# Setup SSL
echo "[$(date)] Setting up SSL..."
mkdir -p /etc/nginx/ssl
echo "${var.cloudflare_cert}" > /etc/nginx/ssl/cloudflare.crt
echo "${var.cloudflare_key}" > /etc/nginx/ssl/cloudflare.key
chmod 600 /etc/nginx/ssl/cloudflare.key

# Setup authentication
echo "[$(date)] Setting up authentication..."
htpasswd -bc /etc/nginx/.htpasswd ${var.staging_username} ${var.staging_password}
chown root:www-data /etc/nginx/.htpasswd
chmod 640 /etc/nginx/.htpasswd

# Configure Nginx
echo "[$(date)] Configuring Nginx..."
cat > /etc/nginx/sites-available/staging << 'EOL'
# Production server (no auth)
server {
    listen 443 ssl;
    server_name kerryai.app;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        return 200 'KerryAI - Coming Soon!\n';
        add_header Content-Type text/plain;
    }
}

# Staging server (with auth)
server {
    listen 443 ssl;
    server_name staging.kerryai.app;

    # SSL configuration (shared with production)
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    
    # Basic auth for all locations
    auth_basic "Kerry AI Staging";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        set $auth_user "";
        set $auth_pass "";
        
        if ($http_authorization ~ "^Basic (.*)$") {
            set $auth $1;
        }

        if ($http_authorization = "") {
            add_header WWW-Authenticate 'Basic realm="Kerry AI Staging"' always;
            return 401 'Authentication required\n';
        }

        if ($auth != "a2Vycnk6dmVkQ2VjLTR6aXpqaS1kaWhwaXI=") {
            add_header WWW-Authenticate 'Basic realm="Kerry AI Staging"' always;
            return 401 'Invalid credentials\n';
        }

        return 200 'Kerry AI Staging - Coming Soon!\n';
        add_header Content-Type text/plain;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name kerryai.app staging.kerryai.app;
    return 301 https://$host$request_uri;
}
EOL

# Enable configuration
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/

# Test and restart Nginx
echo "[$(date)] Testing and restarting Nginx..."
nginx -t && systemctl restart nginx || {
    echo "Nginx configuration test failed!"
    exit 1
}

echo "[$(date)] Setup complete successfully!"
EOF
}