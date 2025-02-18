# Terraform State Management

## Overview
This document explains how Terraform state is managed in the Kerry project using Hetzner Object Storage as a backend.

## State Storage
We use Hetzner Object Storage (S3-compatible) to store Terraform state remotely. The configuration is in `terraform/versions.tf`:

```hcl
backend "s3" {
    bucket                      = "kerry-terraform-state"
    key                         = "terraform.tfstate"
    region                      = "eu-central-1"
    endpoints = { s3 = "https://nbg1.your-objectstorage.com" }
    use_path_style = true
    skip_credentials_validation = true
    skip_metadata_api_check = true
    skip_region_validation = true
    skip_requesting_account_id = true
    skip_s3_checksum = true
}
```
## Why Remote State?
1. **Collaboration**: Multiple team members can access and manage infrastructure
2. **Backup**: State is safely stored and backed up in Hetzner's infrastructure
3. **CI/CD Integration**: GitHub Actions can access state for automated deployments
4. **State Locking**: Prevents concurrent modifications
5. **Version History**: Changes to state are tracked

## Credentials
State access requires Hetzner Storage credentials:
- Access Key ID
- Secret Access Key

These are stored as GitHub Environment Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Local Development
To work with state locally, create `backend.hcl`:

```hcl
access_key = "${{ secrets.AWS_ACCESS_KEY_ID }}"
secret_key = "${{ secrets.AWS_SECRET_ACCESS_KEY }}"
```

Run `terraform init -backend-config=backend.hcl` to initialize the backend.

## GitHub Actions
The GitHub Actions workflow uses the following steps:

1. **Checkout**: Fetches the Terraform code from the repository
2. **Setup Terraform**: Initializes Terraform configuration
3. **Create Backend Config**: Creates a backend configuration file
4. **Terraform Init**: Initializes the backend and fetches providers
5. **Terraform Format**: Checks formatting
6. **Terraform Plan**: Generates an execution plan
7. **Terraform Apply**: Applies the changes

## State Locking
Terraform uses a lock file to prevent concurrent modifications to the state. The lock file is stored in the repository:

```
terraform.lock.hcl
```

## State Management

### Initialization

```bash
terraform init -backend-config=backend.hcl
```

### Formatting

```bash
terraform fmt
```

### Planning

```bash
terraform plan
```

### Applying

```bash
terraform apply
```

## State Locking

```bash
terraform lock
```