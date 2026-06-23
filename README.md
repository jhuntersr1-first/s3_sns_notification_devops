# S3 → Lambda → SNS Upload Notification Pipeline

![Terraform CI](https://img.shields.io/github/actions/workflow/status/jhuntersr1-first/s3_sns_notification_devops/terraform-ci.yml?label=Terraform%20CI&logo=githubactions)
![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform)
![AWS](https://img.shields.io/badge/Cloud-AWS-orange?logo=amazonaws)
![S3](https://img.shields.io/badge/Storage-Amazon%20S3-569A31?logo=amazons3)
![Lambda](https://img.shields.io/badge/Compute-AWS%20Lambda-FF9900?logo=awslambda)
![SNS](https://img.shields.io/badge/Messaging-Amazon%20SNS-FF4F00)
![Python](https://img.shields.io/badge/Runtime-Python%203.12-blue?logo=python)
![IAM](https://img.shields.io/badge/Security-Least%20Privilege-red?logo=amazonaws)
![Serverless](https://img.shields.io/badge/Architecture-Event%20Driven-blueviolet)
![License](https://img.shields.io/badge/License-MIT-blue)

## Overview

This module provisions a fully automated, event-driven notification pipeline on AWS: any object created in an S3 bucket triggers a Lambda function, which publishes a formatted message to an SNS topic for delivery to a subscribed email address. Common real-world applications include upload auditing, ingestion-pipeline alerting, and lightweight monitoring for buckets that receive infrequent or business-critical files.

Every resource in this stack — the bucket, the function, the topic, and the IAM roles connecting them — is defined and deployed through Terraform. There are no manual console steps required to provision the infrastructure.

## Architecture

```
S3 Bucket
    │  s3:ObjectCreated:*
    ▼
Lambda Function  ──►  SNS Topic  ──►  Email Subscription
(S3ToSNSLambda)        (upload_notifications)
```

The S3 bucket notification triggers the Lambda function on any object-creation event (`Put`, `Post`, `Copy`, or multipart upload completion). The Lambda function parses the S3 event payload, formats a human-readable message, and publishes it to the SNS topic, which fans it out to the confirmed email subscription.

## Skills Demonstrated

- Event-driven serverless architecture on AWS (S3 → Lambda → SNS)
- Infrastructure as Code with modular, single-responsibility Terraform files
- IAM least-privilege role design — the Lambda execution role is scoped to `sns:Publish` on a single topic ARN, not a managed full-access policy
- Defense-in-depth resource policies — both the IAM role and the SNS topic policy independently restrict who can publish, with the topic policy further conditioned on the exact Lambda function ARN via `aws:SourceArn`
- S3 bucket hardening via `aws_s3_bucket_public_access_block`
- Structured error handling and CloudWatch logging in the Lambda function, including per-record exception isolation so one malformed event doesn't fail the entire batch
- Terraform-managed Lambda packaging (`archive_file` + `local_file`) without committing build artifacts to source control
- CI/CD for infrastructure: GitHub Actions pipeline runs `fmt`, `init`, `validate`, and a Checkov security scan on every pull request, posts the plan output as a PR comment for review, and gates `apply` behind a merge to `main`
- Remote state management with an S3 backend and DynamoDB state locking, provisioned through a self-contained bootstrap stack to avoid the chicken-and-egg problem of using Terraform to create its own backend
- A least-privilege, custom-scoped IAM user for the CI/CD pipeline itself, built and iterated on as a managed policy (not an inline policy, which hits a 2048-byte size ceiling on IAM users)
- A manually-gated destroy workflow (`workflow_dispatch` with a typed confirmation phrase) — deliberately not wired to `push` or `pull_request`, since an automatic destroy trigger would let anyone who can merge to `main` tear down the stack as a side effect

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── terraform-ci.yml      # PR checks: fmt, validate, Checkov, plan
│       ├── terraform-apply.yml   # Deploy on merge to main
│       └── terraform-destroy.yml # Manual, confirmation-gated teardown
├── bootstrap/                    # One-time setup for remote state backend + CI IAM user
│   ├── main.tf                   # S3 bucket + DynamoDB lock table
│   ├── iam.tf                    # Scoped IAM user/policies for the CI/CD pipeline
│   ├── variables.tf
│   └── outputs.tf
├── main.tf            # Provider, version constraints, S3 backend config, data sources
├── variables.tf        # Input variable definitions
├── s3.tf               # S3 bucket, public access block, event notification
├── lambda.tf           # Lambda IAM role/policies, function resource
├── lambda/
│   └── sns_notify.py   # Lambda source code (zipped by the archive provider)
├── sns.tf              # SNS topic, topic policy, email subscription
├── outputs.tf          # Output values (bucket name, ARNs, subscription reminder)
├── .gitignore
└── README.md
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3.0 (only needed locally if running the bootstrap stack or testing manually — the GitHub Actions pipeline installs its own)
- AWS CLI configured with credentials that have permission to create S3, Lambda, SNS, IAM, and DynamoDB resources (for local/bootstrap use)
- A GitHub repository with Actions enabled, if using the CI/CD pipeline
- A valid email address to receive notifications

## Usage (manual / local)

This is the fastest way to test the stack directly. For the intended deployment path via GitHub Actions, see [CI/CD Setup](#cicd-setup) below.

1. Clone the repository and navigate into it.

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review the plan, supplying your notification email (required — there is no default):
   ```bash
   terraform plan -var="notification_email=you@example.com"
   ```

4. Apply:
   ```bash
   terraform apply -var="notification_email=you@example.com"
   ```

5. **Confirm the SNS subscription.** After `apply` completes, AWS sends a confirmation email to the address you provided. The subscription remains in `PendingConfirmation` status — and no notifications will be delivered — until you click the confirmation link. The `subscription_note` output will remind you of this every time you run `terraform apply` or `terraform output`.

> To avoid passing the email on the command line every time, create a `terraform.tfvars` file (already excluded via `.gitignore`):
> ```hcl
> notification_email = "you@example.com"
> ```

## CI/CD Setup

This repo is designed to deploy through GitHub Actions rather than repeated local `terraform apply` runs. Set this up once, in order:

### 1. Provision the remote state backend and CI IAM user

```bash
cd bootstrap
terraform init
terraform apply
```

This creates an S3 bucket (versioned, encrypted, public access blocked) and a DynamoDB table for state locking, plus a dedicated IAM user (`github-actions-s3-sns-lambda-ci`) with two scoped managed policies — one for state backend access, one for managing this project's specific S3 bucket, Lambda function, SNS topic, and the Lambda's IAM role by exact name. Keep this stack's own state local — don't add a backend block to it, or you recreate the exact chicken-and-egg problem it exists to solve.

If you change `state_bucket_name` or `lock_table_name` from the defaults in `bootstrap/variables.tf`, update the matching values in the `backend "s3"` block in the root `main.tf`.

Retrieve the CI user's credentials:
```bash
terraform output ci_access_key_id
terraform output -raw ci_secret_access_key
```

> **Note:** least-privilege scoping for Lambda, S3, and IAM was arrived at empirically — the Terraform AWS provider checks several read-only "describe" actions during every `plan`/`apply` refresh (e.g. `s3:GetAccelerateConfiguration`, `s3:GetLifecycleConfiguration`, `lambda:GetFunctionCodeSigningConfig`) that aren't obvious from the resource's configured attributes alone. Expect a tight policy to need a round or two of "access denied → add the specific action" iteration before it's fully quiet.

### 2. Migrate the root module to remote state

From the repo root (not `bootstrap/`):
```bash
terraform init -migrate-state
```
Terraform detects the `backend "s3"` block in `main.tf` and offers to copy existing local state into the new bucket. Confirm yes.

### 3. Add GitHub repository secrets

Under **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | `ci_access_key_id` output from the bootstrap stack |
| `AWS_SECRET_ACCESS_KEY` | `ci_secret_access_key` output from the bootstrap stack |
| `NOTIFICATION_EMAIL` | Email address that should receive S3 upload notifications |

> A missing or misspelled secret name fails silently — GitHub Actions substitutes an empty string rather than erroring, which can be dangerous for values like `notification_email` (an empty value would force-replace the live SNS subscription rather than just failing the run). Always check the masked `***` appears for every expected secret in the workflow's env dump before trusting a run.

### 4. (Optional) Add a manual approval gate on apply

`terraform-apply.yml` and `terraform-destroy.yml` both target a GitHub **environment** named `production`. Create one under **Settings → Environments** and add required reviewers if you want a human approval step between trigger and execution.

### Pipeline behavior

| Trigger | Workflow | What runs |
|---|---|---|
| Pull request opened/updated against `main` | `terraform-ci.yml` | `fmt -check`, `init`, `validate`, Checkov scan, `plan` — results posted as a PR comment |
| Push/merge to `main` | `terraform-apply.yml` | `init`, `apply -auto-approve` (gated by the `production` environment if configured) |
| Manual only — Actions tab → "Run workflow" | `terraform-destroy.yml` | Requires typing `destroy` as input; empties the S3 bucket, then `destroy -auto-approve` |

`apply` never runs on a pull request, only on `main` after merge — so every infrastructure change is visible as a reviewed plan before it executes. `destroy` never runs automatically under any circumstance — see [Cleanup](#cleanup) below for why it's deliberately manual-only.

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `aws_region` | AWS region to deploy resources into | `string` | `"us-east-1"` |
| `bucket_name` | Globally unique name for the S3 bucket | `string` | `"s3snslambda-project"` |
| `sns_topic_name` | Name for the SNS topic | `string` | `"s3-email-notification"` |
| `notification_email` | Email address to receive upload notifications | `string` | *(required, no default)* |
| `lambda_function_name` | Name of the Lambda function | `string` | `"S3ToSNSLambda"` |

## Outputs

| Name | Description |
|---|---|
| `s3_bucket_name` | Name of the S3 upload bucket |
| `sns_topic_arn` | ARN of the SNS notification topic |
| `lambda_function_name` | Name of the Lambda function |
| `lambda_function_arn` | ARN of the Lambda function |
| `subscription_note` | Reminder to confirm the SNS email subscription |

## Testing

1. Confirm the SNS email subscription (see Usage, step 5) — notifications won't deliver until this is done.
2. Get the bucket name from Terraform output:
   ```bash
   terraform output s3_bucket_name
   ```
3. Upload a test file:
   ```bash
   aws s3 cp ./test-file.txt s3://$(terraform output -raw s3_bucket_name)/
   ```
4. Within 15–30 seconds, check the inbox for the configured `notification_email`. The message includes the bucket name, object key, size, region, event type, and a direct console link to the file.

For troubleshooting, inspect Lambda execution logs in **CloudWatch → Log groups → `/aws/lambda/S3ToSNSLambda`**:
```bash
aws logs tail /aws/lambda/S3ToSNSLambda --since 1h
```
> On Git Bash / MINGW64 (Windows), a leading `/` in CLI arguments can get mangled by path translation, causing a confusing `InvalidParameterException` even on syntactically correct commands. Prefix with `MSYS_NO_PATHCONV=1` if you see that error on an otherwise-correct AWS CLI call.

| Symptom | Likely Cause | Resolution |
|---|---|---|
| No email received | Subscription not confirmed | Check the inbox/spam folder for the AWS confirmation email and click the link |
| No email received | `SNS_TOPIC_ARN` not passed to Lambda | Verify `terraform apply` completed successfully and the environment variable is set on the function |
| Lambda execution error | IAM permissions issue | Confirm `aws_iam_role_policy_attachment.lambda_basic` and `aws_iam_role_policy.lambda_sns_publish` applied without error |
| Lambda not triggered | Event notification misconfigured | Confirm `aws_s3_bucket_notification.trigger_lambda` applied and `aws_lambda_permission.allow_s3_invoke` exists before it |
| SNS publish error | Topic policy too restrictive | Verify the `aws:SourceArn` condition in `sns.tf` matches the deployed Lambda function ARN |
| CI pipeline: `AccessDenied` on a `Get*`/describe action | CI IAM policy missing a read-only permission the provider checks during refresh | Add the specific action named in the error to `bootstrap/iam.tf`'s `ci_app_resources` policy, then `terraform apply` in `bootstrap/` |
| CI pipeline: `LimitExceeded... Maximum policy size` | Inline IAM policy exceeded 2048 bytes | Already resolved in this repo by using `aws_iam_policy` (managed) + `aws_iam_user_policy_attachment` instead of `aws_iam_user_policy` (inline) |

## Cleanup

There are two ways to tear down the root module's resources (the S3 bucket, Lambda function, SNS topic, and related IAM role — **not** the bootstrap stack's state backend or CI user, which are left running deliberately; see below).

### Option A — Local

```bash
aws s3 rm s3://$(terraform output -raw s3_bucket_name)/ --recursive
terraform destroy -var="notification_email=you@example.com"
```
The bucket must be emptied first — `aws_s3_bucket` destroy fails if the bucket still contains objects.

### Option B — GitHub Actions (manual trigger)

Go to the **Actions** tab → **Terraform Destroy** (left sidebar) → **Run workflow** → type `destroy` in the confirmation field → **Run workflow**.

This workflow runs on `workflow_dispatch` only — it is **never** triggered by a push or pull request. A destroy wired to those events would let anyone who can merge to `main` delete the stack as a side effect of an unrelated change; requiring a human to manually trigger it and type a confirmation phrase is a deliberate guardrail, not an oversight. The workflow empties the S3 bucket automatically before running `terraform destroy -auto-approve`.

### Bootstrap stack (state backend + CI IAM user)

Left running by design in normal use — it's cheap (DynamoDB pay-per-request, a near-empty S3 bucket) and re-running the root module later doesn't require redoing any backend setup. If you do want to tear it down (e.g. permanently retiring the project), do it manually, last, from `bootstrap/`:
```bash
cd bootstrap
terraform destroy
```
This is intentionally **not** automatable from CI — a pipeline should never be able to delete the identity and state backend that controls it.

## Future Improvements

- Add a dead-letter queue (DLQ) for failed Lambda invocations
- Move the SNS topic ARN and other identifiers to AWS Systems Manager Parameter Store or Secrets Manager rather than plain environment variables
- Support multiple notification protocols (SMS, Slack webhook via a second Lambda) in addition to email
- Migrate AWS authentication from static GitHub Secrets to OIDC role assumption (`AssumeRoleWithWebIdentity`), removing the long-lived IAM access key from the pipeline entirely
- Add `terraform plan` drift detection on a schedule (e.g. nightly) to catch manual out-of-band changes
- Pin the Checkov and Terraform provider versions more tightly, and add `tflint` as a complementary static-analysis step

## Acknowledgments

Lambda notification logic originally adapted from [Derrick](https://github.com/derrickSh43/SNSfromS3withLambda/blob/main/SNS.py).
