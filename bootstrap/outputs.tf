output "state_bucket_name" {
  description = "S3 bucket name to use in the root module's backend block"
  value       = aws_s3_bucket.tf_state.id
}

output "lock_table_name" {
  description = "DynamoDB table name to use in the root module's backend block"
  value       = aws_dynamodb_table.tf_lock.id
}

output "ci_access_key_id" {
  description = "Access key ID for the CI/CD IAM user — add to GitHub Secrets as AWS_ACCESS_KEY_ID"
  value       = aws_iam_access_key.ci_pipeline.id
}

output "ci_secret_access_key" {
  description = "Secret access key for the CI/CD IAM user — add to GitHub Secrets as AWS_SECRET_ACCESS_KEY. Retrieve with: terraform output -raw ci_secret_access_key"
  value       = aws_iam_access_key.ci_pipeline.secret
  sensitive   = true
}
