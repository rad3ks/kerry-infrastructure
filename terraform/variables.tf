variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name of the server"
  type        = string
  default     = "kerry-server"
}

variable "server_type" {
  description = "Server type/size"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Server image/OS"
  type        = string
  default     = "ubuntu-22.04"
}

variable "server_location" {
  description = "Server location"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

variable "staging_username" {
  description = "Username for staging basic auth"
  type        = string
  default     = "kerry"
}

variable "staging_password" {
  description = "Password for staging basic auth"
  type        = string
  sensitive   = true
}

variable "cloudflare_cert" {
  description = "Cloudflare Origin Certificate"
  type        = string
  sensitive   = true
}

variable "cloudflare_key" {
  description = "Cloudflare Private Key"
  type        = string
  sensitive   = true
}
