# ---------------------------------------------------------------
# Bootstrap stack — creates the S3 bucket + DynamoDB table used as
# the remote backend for the main project's Terraform state.
#
# This is a ONE-TIME setup. Run it manually, once, with local state:
#
#   cd bootstrap
#   terraform init
#   terraform apply
#
# Do NOT add a backend block here — this stack's own state stays
# local (or you'll recreate the chicken-and-egg problem this exists
# to solve). After it applies, copy the bucket/table names into the
# backend block in ../main.tf and run `terraform init -migrate-state`
# in the root module.
# ---------------------------------------------------------------

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  tags = {
    Project = "s3-sns-lambda"
    Purpose = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = "s3-sns-lambda"
    Purpose = "terraform-state-lock"
  }
}
