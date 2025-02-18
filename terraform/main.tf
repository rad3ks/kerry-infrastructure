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
    environment = var.server_name == "kerry-production" ? "production" : "staging"
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.ssh_private_key
    host        = self.ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to complete
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      
      # Wait for any system locks
      "while [ -f /var/lib/apt/lists/lock ] || [ -f /var/lib/dpkg/lock-frontend ]; do sleep 2; done",
      
      # Update and install packages
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y nginx apache2-utils",
      
      # Create Nginx config
      "cat > /etc/nginx/sites-available/default << 'EOL'",
      "server {",
      "    listen 80;",
      "    server_name staging.kerryai.app;",
      "",
      "    auth_basic \"Kerry AI Staging\";",
      "    auth_basic_user_file /etc/nginx/.htpasswd;",
      "",
      "    location / {",
      "        proxy_pass http://localhost:8000;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "    }",
      "}",
      "EOL",
      
      # Setup auth
      "htpasswd -bc /etc/nginx/.htpasswd ${var.staging_username} ${var.staging_password}",
      
      # Enable and start Nginx
      "systemctl enable nginx",
      "systemctl start nginx",
      "nginx -t && systemctl restart nginx"
    ]
  }
}