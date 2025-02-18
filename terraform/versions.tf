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
    key                         = "terraform.tfstate"
    region                      = "eu-central-1"
    endpoint                    = "https://nbg1.your-objectstorage.com"
    skip_credentials_validation = true
    skip_metadata_api_check    = true
    skip_region_validation     = true
  }
}
