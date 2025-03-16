#!/bin/bash
set -e

echo "[$(date)] Configuring nginx..."

# Create SSL directory and set permissions
mkdir -p /etc/nginx/ssl
chmod 700 /etc/nginx/ssl

# Install SSL certificates
echo "${cloudflare_cert}" > /etc/nginx/ssl/cloudflare.crt
echo "${cloudflare_key}" > /etc/nginx/ssl/cloudflare.key
chmod 600 /etc/nginx/ssl/cloudflare.key

# Create web directories
mkdir -p /var/www/html/staging
chmod 755 /var/www/html/staging

# Create login.html with proper credentials
cat > /var/www/html/staging/login.html << 'HTMLEOF'
${login_html}
HTMLEOF

# Configure Nginx
cat > /etc/nginx/sites-available/staging << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name staging.kerryai.app;
    
    ssl_certificate /etc/nginx/ssl/cloudflare.crt;
    ssl_certificate_key /etc/nginx/ssl/cloudflare.key;
    
    # SSL parameters
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    
    root /var/www/html/staging;
    
    # Serve login.html directly
    location = /login.html {
        add_header Content-Type text/html;
    }
    
    # Root path - either serve login or proxy to frontend
    location = / {
        if ($cookie_auth = "") {
            return 302 /login.html;
        }
        
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # All other paths go to the frontend
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOL

# Enable configuration
ln -sf /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and restart Nginx
nginx -t && systemctl restart nginx

echo "[$(date)] Nginx configuration completed successfully!" 