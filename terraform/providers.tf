variable "server_name" {
  description = "Name of the server"
  type        = string
  default     = "kerry-production"
}

variable "server_type" {
  description = "Server type/size"
  type        = string
  default     = "cx21" # 2 vCPU, 4 GB RAM
}

variable "server_location" {
  description = "Server location"
  type        = string
  default     = "nbg1" # Nuremberg
}

variable "server_image" {
  description = "Server image"
  type        = string
  default     = "ubuntu-22.04"
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
  sensitive   = true
}