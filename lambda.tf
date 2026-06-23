# ---------------------------------------------------------------
# Lambda Deployment Package
# Source lives in ./lambda/sns_notify.py — zipped directly by the
# archive provider. No inline heredoc generation.
# ---------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/sns_notify.zip"
}

# ---------------------------------------------------------------
# IAM Role for Lambda
# ---------------------------------------------------------------

resource "aws_iam_role" "lambda_exec" {
  name = "${var.lambda_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "s3-sns-lambda"
  }
}

# Basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Publish — scoped to only this topic (least privilege)
resource "aws_iam_role_policy" "lambda_sns_publish" {
  name = "SNSPublishToNotificationTopic"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.upload_notifications.arn
      }
    ]
  })
}

# ---------------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------------

resource "aws_lambda_function" "s3_to_sns" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "sns_notify.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.upload_notifications.arn
    }
  }

  tags = {
    Project = "s3-sns-lambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_sns_publish,
  ]
}
