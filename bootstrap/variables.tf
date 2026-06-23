variable "aws_region" {
  description = "AWS region to deploy the state backend into"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform remote state bucket"
  type        = string
  default     = "s3-sns-lambda-tf-state"
}

variable "lock_table_name" {
  description = "Name for the DynamoDB state lock table"
  type        = string
  default     = "s3-sns-lambda-tf-lock"
}
