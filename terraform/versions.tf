terraform {
  required_version = ">= 1.0.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45.0"
    }
  }

  backend "s3" {
    bucket                      = "kerry-terraform-state"
    key                         = "kerry/terraform.tfstate"
    region                      = "eu-central-1"
    endpoints                   = { s3 = "https://storage.hetzner.com" }
    use_path_style             = true
    skip_credentials_validation = true
    skip_metadata_api_check    = true
    skip_region_validation     = true
    skip_requesting_account_id = true
  }
}
