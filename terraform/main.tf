# Create SSH key
resource "hcloud_ssh_key" "default" {
  name       = "kerry-ssh-key"
  public_key = var.ssh_public_key
}

# Create a basic firewall
resource "hcloud_firewall" "default" {
  name = "kerry-firewall"

  # SSH access - Restricted to your home IP
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "109.173.177.150/32" # Your home IP
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

  provisioner "file" {
    source      = "files/nginx.conf"
    destination = "/tmp/nginx.conf"
  }

  provisioner "file" {
    source      = "files/setup-auth.sh"
    destination = "/tmp/setup-auth.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y nginx apache2-utils",
      "mv /tmp/nginx.conf /etc/nginx/sites-available/default",
      "ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default",
      "chmod +x /tmp/setup-auth.sh",
      "export STAGING_USERNAME='${var.staging_username}'",
      "export STAGING_PASSWORD='${var.staging_password}'",
      "/tmp/setup-auth.sh",
      "systemctl enable nginx",
      "systemctl start nginx",
      "systemctl restart nginx"
    ]
  }
}