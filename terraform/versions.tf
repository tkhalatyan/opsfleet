terraform {
  # >= 1.10 for native S3 state locking (use_lockfile) in the optional remote backend.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4.0"
    }
  }

  # State is local by default so the POC works with zero setup.
  # For team use, copy backend.tf.example to backend.tf and run `terraform init -migrate-state`.
}
