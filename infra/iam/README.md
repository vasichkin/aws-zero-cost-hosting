# IAM policies for the deploy user

Two customer-managed policies, written for this repository's resources (placeholders, no account data):

| File | Attach to | Purpose |
|---|---|---|
| `bootstrap-policy.json` | whoever runs `infra/bootstrap` (once) | Create the state bucket |
| `credentials-admin-policy.json` | an administrator (not the limited user) | Lets the administrator create the limited user and manage its console password, access keys and policy attachments, and nothing else |
| `deploy-policy.json` | the user that runs `tofu apply` / `destroy` / `aws s3 sync` for dev and prod | State access, S3 site bucket and content, CloudFront (+ invalidation), ACM, API Gateway, Lambda + its role and log group, SES, Budgets |

`deploy-policy.json` is about 3.5 KB, under the 6,144-character managed-policy limit.

## Create and attach

`make setup` (`scripts/setup.sh`) can patch the placeholders for you: it asks for the account ID and the IAM user and writes the finished policies to `infra/iam/rendered/` (gitignored, never commit them). Skip to the `aws iam` commands below and use those files. To do it by hand instead, substitute the placeholders in the templates, then create the policies and attach them with credentials that may manage IAM (an administrator, or root):

| Placeholder | Value |
|---|---|
| `PROJECT` | `project_name` from `infra/environments/prod/terraform.tfvars` |
| `PROJECT_SAFE` | `PROJECT` with dots replaced by `-` (Lambda, role and log group names) |
| `REGION` | `aws_region` |
| `ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` |
| `STATE_BUCKET` | `state_bucket_name` from `infra/bootstrap/terraform.tfvars` |
| `SITE_BUCKET` | `site_bucket_name` from `infra/environments/prod/terraform.tfvars` |
| `DEV_SITE_BUCKET` | `site_bucket_name` from `infra/environments/dev/terraform.tfvars` |

Replace `PROJECT_SAFE` before `PROJECT` and `DEV_SITE_BUCKET` before `SITE_BUCKET`, as each is a prefix of the other. Keep the rendered files out of git. Then, for each policy:

```bash
aws iam create-policy --policy-name <PROJECT_SAFE>-tofu-deploy --policy-document file://infra/iam/rendered/deploy-policy.json
aws iam attach-user-policy --user-name <user> --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/<PROJECT_SAFE>-tofu-deploy
```

Policy names are `<PROJECT_SAFE>-tofu-deploy`, `<PROJECT_SAFE>-tofu-bootstrap` and `<PROJECT_SAFE>-tofu-credentials-admin`. To change an existing policy, create a new default version with `aws iam create-policy-version --set-as-default` (IAM keeps at most 5). Detach the bootstrap policy once bootstrap is done.

## What is scoped and what is not

- **Scoped by name:** the prod and dev site buckets (`SITE_BUCKET`, `DEV_SITE_BUCKET`), Lambda functions, IAM roles and log groups (`PROJECT_SAFE-*`), budgets, API Gateway in `REGION`, the state bucket.
- **Cannot be scoped before creation, so `Resource: "*"` with a region condition:** CloudFront (distributions, functions, OACs), ACM (`us-east-1` only), SES identities. CloudFront is global.
- **S3 actions are listed explicitly** and scoped to the project's own buckets (state bucket for bootstrap, the two site buckets for deploy). The list includes the read-only `Get*` calls the AWS provider makes when refreshing a bucket (accelerate, ACL, CORS, logging, object lock, ownership, request payment, website, replication). If a plan still fails with `AccessDenied` on an S3 action, add that one action to the bucket statement.
- `iam:AttachRolePolicy` is limited to `AWSLambdaBasicExecutionRole`; inline role policies (`iam:PutRolePolicy`) are allowed, which the Lambda module needs.

## Caveats

- **Privilege escalation:** a user who can create roles and put role policies can create a role with more access than they have. If your organization uses a permissions boundary, require it on `iam:CreateRole`, matching `iam_permissions_boundary_arn`:
  ```json
  "Condition": {"StringEquals": {"iam:PermissionsBoundary": "arn:aws:iam::ACCOUNT_ID:policy/YourBoundaryPolicy"}}
  ```
- **Not tested against a live apply.** The action lists come from reading the Terraform resources, not from a CloudTrail run. Expect to add a missing action after a provider upgrade or on the first full apply. Check `AccessDenied` messages or CloudTrail for the exact action.
- State locking is S3-native, so the existing object permissions on the state bucket (including the `.tflock` object) are all that is needed.

## Credentials admin policy

`credentials-admin-policy.json` is for an **administrator who manages the limited deploy user**, not for the deploy user itself, so the deploy permissions stay unchanged. It is scoped to the one user named by `IAM_USER` (placeholder `TARGET_USER`):

- **User:** create, get, tag and delete that user.
- **Console:** create, read, update and delete its login profile (set a one-time password and force a reset).
- **CLI keys:** create, list, rotate and delete its access keys, and see last use.
- **MFA:** list and deactivate its MFA devices (reset a lost device).
- **Policies:** attach or detach only `<project>-tofu-*` policies, and create or update those policies.

It cannot touch any other user or attach any other policy.

**The root user needs no policy.** IAM policies do not restrict the account root user, so root can create the policies and manage the limited user directly. Root should still be used only for this kind of one-off setup, with MFA and no access keys. For regular use, attach this policy to a separate admin IAM user (`IAM_ADMIN_USER`). Created keys and passwords are long-lived secrets: hand them over securely and prefer Identity Center or an assumable role where you can.
