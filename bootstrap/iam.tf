# ---------------------------------------------------------------
# CI/CD IAM User — used by GitHub Actions to plan/apply the root
# module (and, intentionally, NOT permitted to touch bootstrap's
# own state backend resources beyond what's needed to use them).
#
# This is part of the bootstrap stack deliberately: a pipeline
# should never be able to modify the identity/permissions that
# control itself. Changes here require a human running
# `terraform apply` from this directory by hand.
#
# Future improvement (tracked in README): replace this static-key
# IAM user with OIDC federation (AssumeRoleWithWebIdentity), which
# removes the need for any long-lived credential entirely.
# ---------------------------------------------------------------

resource "aws_iam_user" "ci_pipeline" {
  name = var.ci_user_name

  tags = {
    Project = "s3-sns-lambda"
    Purpose = "github-actions-ci-cd"
  }
}

resource "aws_iam_access_key" "ci_pipeline" {
  user = aws_iam_user.ci_pipeline.name
}

# ---------------------------------------------------------------
# Policy: state backend access
# Scoped to exactly the bucket/table this project's root module
# uses for remote state — not "all S3" or "all DynamoDB."
#
# Uses a customer-managed policy (rather than an inline policy)
# because inline policies on IAM users are capped at 2048 bytes —
# easy to exceed once several services are scoped individually.
# Managed policies cap at 6144 bytes and are independently visible
# in the IAM console, which is also just a cleaner pattern.
# ---------------------------------------------------------------

resource "aws_iam_policy" "ci_state_backend" {
  name        = "CIStateBackendAccess"
  description = "Allows the CI/CD user to read/write Terraform remote state and acquire/release the DynamoDB lock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.tf_state.arn}/*"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Sid    = "StateLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.tf_lock.arn
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ci_state_backend" {
  user       = aws_iam_user.ci_pipeline.name
  policy_arn = aws_iam_policy.ci_state_backend.arn
}

# ---------------------------------------------------------------
# Policy: application resource management
# Scoped by name pattern to this project's specific resources.
# Name-pattern scoping (rather than exact ARN) is necessary here
# because Terraform creates these resources — their exact ARNs
# don't exist before the first apply.
# ---------------------------------------------------------------

resource "aws_iam_policy" "ci_app_resources" {
  name        = "CIAppResourceManagement"
  description = "Allows the CI/CD user to manage this project's specific S3 bucket, Lambda function, SNS topic, and the Lambda's IAM role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketManagement"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucket*",
          "s3:PutBucket*",
          "s3:GetAccelerateConfiguration",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.app_bucket_name}",
          "arn:aws:s3:::${var.app_bucket_name}/*",
        ]
      },
      {
        Sid    = "LambdaManagement"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:ListVersionsByFunction",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags",
        ]
        Resource = "arn:aws:lambda:*:*:function:${var.app_lambda_function_name}"
      },
      {
        Sid    = "SNSManagement"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:TagResource",
          "sns:UntagResource",
          "sns:ListTagsForResource",
        ]
        Resource = "arn:aws:sns:*:*:${var.app_sns_topic_name}"
      },
      {
        Sid    = "IAMRoleManagementForLambda"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::*:role/${var.app_lambda_function_name}-role"
      },
      {
        Sid      = "STSCallerIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ci_app_resources" {
  user       = aws_iam_user.ci_pipeline.name
  policy_arn = aws_iam_policy.ci_app_resources.arn
}
