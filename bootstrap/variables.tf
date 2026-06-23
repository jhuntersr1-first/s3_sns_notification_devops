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

variable "ci_user_name" {
  description = "Name for the IAM user used by the GitHub Actions CI/CD pipeline"
  type        = string
  default     = "github-actions-s3-sns-lambda-ci"
}

# --- Names of the application resources this CI user must manage ---
# These must match the values used in the root module's variables.tf
# (bucket_name, lambda_function_name, sns_topic_name). They're
# duplicated here, rather than shared, because bootstrap and the
# root module are intentionally separate Terraform configurations
# with no direct dependency on each other.

variable "app_bucket_name" {
  description = "Name of the application S3 upload bucket (must match root module's bucket_name)"
  type        = string
  default     = "s3snslambda-project"
}

variable "app_lambda_function_name" {
  description = "Name of the application Lambda function (must match root module's lambda_function_name)"
  type        = string
  default     = "S3ToSNSLambda"
}

variable "app_sns_topic_name" {
  description = "Name of the application SNS topic (must match root module's sns_topic_name)"
  type        = string
  default     = "s3-email-notification"
}
