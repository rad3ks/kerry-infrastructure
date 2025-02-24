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
    environment = "general"
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

# Pull the latest frontend image
docker pull ${var.registry_url}/kerry-frontend:latest

# Create and start the frontend container
docker run -d \
  --name kerry-frontend \
  -p 3000:80 \
  --restart always \
  ${var.registry_url}/kerry-frontend:latest

# Install nginx
echo "[$(date)] Installing nginx..."
apt-get install -y nginx

# Clone repositories
git clone ${var.frontend_repo_url} /opt/kerry/frontend
git clone ${var.backend_repo_url} /opt/kerry/backend

# Create necessary directories
mkdir -p /var/www/html/staging
mkdir -p /etc/nginx/ssl

# Create login page
cat > /var/www/html/staging/login.html << 'HTMLEOF'
${templatefile("${path.module}/files/login.html", {
  staging_username = var.staging_username,
  staging_password = var.staging_password,
  auth_token = base64encode("${var.staging_username}:${var.staging_password}")
})}
HTMLEOF

# Setup SSL
echo "${var.cloudflare_cert}" > /etc/nginx/ssl/cloudflare.crt
echo "${var.cloudflare_key}" > /etc/nginx/ssl/cloudflare.key
chmod 600 /etc/nginx/ssl/cloudflare.key

# Create error messages map
cat > /etc/nginx/conf.d/error_messages.conf << 'EOL'
map $status $error_message {
    400 "Bad request - The server could not understand your request.";
    401 "Unauthorized - Authentication is required.";
    403 "Forbidden - You don't have permission to access this resource.";
    404 "Not Found - The requested resource does not exist.";
    408 "Request Timeout - The server timed out waiting for the request.";
    429 "Too Many Requests - Please slow down your requests.";
    500 "Internal Server Error - Something went wrong on our end.";
    502 "Bad Gateway - The server received an invalid response.";
    503 "Service Unavailable - Kerry is experiencing high load.";
    504 "Gateway Timeout - The server took too long to respond.";
    default "An unexpected error occurred.";
}
EOL

# Create error page
cat > /var/www/html/error.html << 'HTMLEOF'
${file("${path.module}/files/error.html")}
HTMLEOF

# Configure Nginx
cat > /etc/nginx/sites-available/staging << EOL
# Create error messages map
map \$status \$error_message {
    400 "Bad request - The server could not understand your request.";
    401 "Unauthorized - Authentication is required.";
    403 "Forbidden - You don't have permission to access this resource.";
    404 "Not Found - The requested resource does not exist.";
    408 "Request Timeout - The server timed out waiting for the request.";
    429 "Too Many Requests - Please slow down your requests.";
    500 "Internal Server Error - Something went wrong on our end.";
    502 "Bad Gateway - The server received an invalid response.";
    503 "Service Unavailable - Kerry is experiencing high load.";
    504 "Gateway Timeout - The server took too long to respond.";
    default "An unexpected error occurred.";
}

# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=1r/s;
limit_req_zone \$binary_remote_addr zone=general_limit:10m rate=10r/s;

# Staging server (with HTML form auth)
server {
    listen 443 ssl;
    server_name staging.kerryai.app;
    
    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # Enable SSI for error pages
    ssi on;
    
    root /var/www/html/staging;

    # Custom error pages for all error codes
    error_page 400 401 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 421 422 423 424 426 428 429 431 451 500 501 502 503 504 505 506 507 508 510 511 = @error;

    # Named location for error handling
    location @error {
        internal;
        ssi on;
        root /var/www/html;
        add_header Content-Type text/html;
        rewrite ^ /error.html break;
    }

    # Serve error page
    location = /error.html {
        internal;
        ssi on;
        root /var/www/html;
        add_header Content-Type text/html;
    }

    # Login page - no auth check here
    location = /login.html {
        limit_req zone=login_limit burst=5 nodelay;
        add_header Content-Type text/html;
    }

    # Docker services only on staging
    location / {
        proxy_pass http://localhost:3000;  # Frontend
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /api {
        proxy_pass http://localhost:8000;  # Backend
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Production server - remove Docker proxy and keep static response
server {
    listen 443 ssl;
    server_name kerryai.app;
    
    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # Enable SSI for error pages
    ssi on;
    
    # Custom error pages for all error codes
    error_page 400 401 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 421 422 423 424 426 428 429 431 451 500 501 502 503 504 505 506 507 508 510 511 = @error;

    # Named location for error handling
    location @error {
        internal;
        ssi on;
        root /var/www/html;
        add_header Content-Type text/html;
        rewrite ^ /error.html break;
    }

    # Serve error page
    location = /error.html {
        internal;
        ssi on;
        root /var/www/html;
        add_header Content-Type text/html;
    }
    
    location / {
        limit_req zone=general_limit burst=20;
        
        # Return 404 for all paths except root
        if ($request_uri != "/") {
            return 404;
        }

        return 200 'KerryAI - Coming Soon!\n';
        add_header Content-Type text/plain;
    }
}

# HTTP to HTTPS redirect for all domains
server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}
EOL

# Enable configuration
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/

# Test and restart Nginx
nginx -t && systemctl restart nginx

echo "[$(date)] Setup completed successfully!"
EOF
}
