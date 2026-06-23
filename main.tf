terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Remote state backend — created by the one-time bootstrap stack
  # in ./bootstrap. Bucket/table names must match its outputs.
  # NOTE: backend blocks cannot use variables; values are hardcoded here.
  backend "s3" {
    bucket         = "s3-sns-lambda-tf-state"
    key            = "s3-sns-lambda/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "s3-sns-lambda-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}