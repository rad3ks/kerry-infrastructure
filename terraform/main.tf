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

# Completely remove nginx and reinstall with all modules
echo "[$(date)] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y nginx nginx-common nginx-full
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx-extras apache2-utils

# Verify Nginx installation and modules
if ! command -v nginx >/dev/null 2>&1; then
    echo "[$(date)] ERROR: Nginx installation failed!"
    exit 1
fi

# Debug: verify auth_basic module
nginx -V 2>&1 | grep auth_basic || echo "WARNING: auth_basic module not found!"

# Create SSL directory
echo "[$(date)] Setting up SSL..."
mkdir -p /etc/nginx/ssl

# Configure SSL certificates
echo "[$(date)] Configuring SSL certificates..."
echo "${var.cloudflare_cert}" > /etc/nginx/ssl/cloudflare.crt
echo "${var.cloudflare_key}" > /etc/nginx/ssl/cloudflare.key
chmod 600 /etc/nginx/ssl/cloudflare.key

# Create fresh .htpasswd with debug output
echo "[$(date)] Setting up authentication..."
echo "Creating .htpasswd file..."
htpasswd -bc /etc/nginx/.htpasswd ${var.staging_username} ${var.staging_password}
echo "Setting permissions..."
chown root:www-data /etc/nginx/.htpasswd
chmod 640 /etc/nginx/.htpasswd
echo "Verifying .htpasswd:"
ls -la /etc/nginx/.htpasswd

# Configure Nginx with debug output
echo "[$(date)] Configuring Nginx..."
echo "Creating staging config..."

# Create staging config
cat > /etc/nginx/sites-available/staging << 'EOL'
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name kerryai.app staging.kerryai.app;
    return 301 https://$host$request_uri;
}

# Production server configuration
server {
    listen 443 ssl;
    server_name kerryai.app;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # Cloudflare recommended SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        return 200 'KerryAI - Coming Soon!';
        add_header Content-Type text/plain;
    }
}

# Staging server configuration
server {
    listen 443 ssl;
    server_name staging.kerryai.app;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # Cloudflare recommended SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
        
    # Add this for debugging
    add_header X-Debug-Server "staging" always;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header Cache-Control "no-store, no-cache, must-revalidate" always;

    # Basic auth at server level
    auth_basic "Kerry AI Staging";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        return 200 'Kerry AI Staging - Coming Soon!';
        add_header Content-Type text/plain;
    }
}
EOL

# Remove default symlink if it exists
rm -f /etc/nginx/sites-enabled/default

# Enable the staging configuration
ln -sf /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/

# Test and restart Nginx
echo "[$(date)] Testing and restarting Nginx..."
nginx -t && systemctl restart nginx || {
    echo "Nginx configuration test failed!"
    exit 1
}

# Verify Nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "[$(date)] ERROR: Nginx failed to start!"
    journalctl -xeu nginx
    exit 1
fi

# After config creation
echo "Verifying Nginx config:"
nginx -t

echo "Enabled sites:"
ls -la /etc/nginx/sites-enabled/

echo "Testing auth file access as www-data:"
sudo -u www-data cat /etc/nginx/.htpasswd

echo "[$(date)] Setup complete successfully!"
EOF
}