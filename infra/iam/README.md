# IAM policies for the deploy user

Two customer-managed policies, written for this repository's resources (placeholders, no account data):

| File | Attach to | Purpose |
|---|---|---|
| `bootstrap-policy.json` | whoever runs `infra/bootstrap` (once) | Create the state bucket |
| `deploy-policy.json` | the user that runs `tofu apply` / `destroy` / `aws s3 sync` for dev and prod | State access, S3 site bucket and content, CloudFront (+ invalidation), ACM, API Gateway, Lambda + its role and log group, SES, Budgets |

`deploy-policy.json` is about 3.5 KB, under the 6,144-character managed-policy limit.

## Placeholders

| Placeholder | Meaning | Example |
|---|---|---|
| `ACCOUNT_ID` | AWS account ID | `123456789012` |
| `REGION` | `aws_region` from `terraform.tfvars` | `eu-north-1` |
| `PROJECT` | `project_name` (resource prefix) | `example.com` |
| `PROJECT_SAFE` | `project_name` with dots replaced by `-` (Lambda, role and log group names) | `example-com` |
| `STATE_BUCKET` | bootstrap output `state_bucket_name` | `example.com-tofu-state` |

## Create and attach

```bash
cd infra/iam
render() {
  sed -e 's/ACCOUNT_ID/123456789012/g' -e 's/REGION/eu-north-1/g' \
      -e 's/PROJECT_SAFE/example-com/g' -e 's/PROJECT/example.com/g' \
      -e 's/STATE_BUCKET/example.com-tofu-state/g' "$1"
}
render deploy-policy.json > /tmp/deploy-policy.json          # keep rendered files out of git
aws iam create-policy --policy-name minimal-aws-deploy --policy-document file:///tmp/deploy-policy.json
aws iam attach-user-policy --user-name <user> --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/minimal-aws-deploy
```

Do the same for `bootstrap-policy.json` if the user also runs bootstrap (and detach it afterwards). Replace `PROJECT_SAFE` before `PROJECT`, as above, because `PROJECT` is a prefix of it.

## What is scoped and what is not

- **Scoped by name:** the site bucket (`PROJECT-*-site`), Lambda functions, IAM roles and log groups (`PROJECT_SAFE-*`), budgets, API Gateway in `REGION`, the state bucket.
- **Cannot be scoped before creation, so `Resource: "*"` with a region condition:** CloudFront (distributions, functions, OACs), ACM (`us-east-1` only), SES identities. CloudFront is global.
- `iam:AttachRolePolicy` is limited to `AWSLambdaBasicExecutionRole`; inline role policies (`iam:PutRolePolicy`) are allowed, which the Lambda module needs.

## Caveats

- **Privilege escalation:** a user who can create roles and put role policies can create a role with more access than they have. If your organization uses a permissions boundary, require it on `iam:CreateRole`, matching `iam_permissions_boundary_arn`:
  ```json
  "Condition": {"StringEquals": {"iam:PermissionsBoundary": "arn:aws:iam::ACCOUNT_ID:policy/YourBoundaryPolicy"}}
  ```
- **Not tested against a live apply.** The action lists come from reading the Terraform resources, not from a CloudTrail run. Expect to add a missing action after a provider upgrade or on the first full apply. Check `AccessDenied` messages or CloudTrail for the exact action.
- State locking is S3-native, so the existing object permissions on the state bucket (including the `.tflock` object) are all that is needed.
