# TODO

Open work items from the DevOps review. Highest priority first.

## High

- [ ] **Distribution-wide error mapping hides API errors.** The `custom_error_response` blocks (403/404 → `/404.html`) in `infra/modules/cloudfront-app` apply to `/api/*` too, so the Lambda's 403 responses (`CAPTCHA_FAILED`, `ORIGIN_NOT_ALLOWED`, `FORBIDDEN`) reach the browser as the HTML 404 page. Serve the 404 page from a function or origin-response logic instead, or stop using 403/404 for API errors.
- [ ] **Move the reCAPTCHA secret to SSM Parameter Store (SecureString).** Today it is a Lambda env var and appears in plaintext in the tofu state. Pass only the parameter name to the Lambda, grant `ssm:GetParameter` on that one parameter, and read it at cold start. Until then, set it via `terraform.tfvars` or `TF_VAR_recaptcha_secret_key_env`.
- [ ] **CI/CD pipeline.** Nothing runs `tofu fmt -check`, `validate`, tflint, checkov/trivy or the Lambda tests, and deploys happen from a laptop. Add a pipeline using OIDC to a least-privilege deploy role, `plan -out` then apply that exact plan, and a manual approval for prod.
- [ ] **Run content deploys from CI.** Content is now synced by `aws s3 sync` from `tofu apply`, so it is out of the state but still needs infra credentials. When CI exists, move the sync and invalidation into a separate job with a role limited to the site bucket and `cloudfront:CreateInvalidation`.
- [ ] **Global-only throttling.** The contact route is limited to 1 request/minute across all visitors, so one bot can lock out real users, and failed reCAPTCHA attempts also use the quota. Per-client limits need WAF (rate-based rule, paid). Also set Lambda reserved concurrency.

## Medium

- [ ] **Initialize AWS users and policies from the wizard.** `scripts/setup.sh` only renders the policies into `infra/iam/rendered/`; an administrator still creates them by hand. Add an `init-users` step (script or make target, run as admin or root, with a dry run) that:
  - creates the managed policies from `infra/iam/rendered/*.json`, or adds a new default version when they exist (IAM keeps at most 5 versions);
  - creates the limited IAM user if missing and attaches the deploy policy, plus the bootstrap policy on request;
  - attaches the credentials-admin policy to the administrator;
  - is idempotent, so re-running it changes nothing when everything exists;
  - prints a summary of what it created and never writes keys or passwords to files or logs.
  - Related: the item below covers the user's console and CLI credentials.
- [ ] **Create the IAM deploy user with make.** Policies are created by hand from the templates in `infra/iam`, and the user must already exist. Add a command (for example `make iam-user USER=<name>`) that creates the IAM user if missing, attaches the policies, and creates credentials:
  - CLI: print a new access key once, or prefer IAM Identity Center / an assumable role over long-lived keys.
  - Console: create a login profile with a generated one-time password and `PasswordResetRequired`, print it once, and require MFA.
  - Never write keys or passwords into the repository or logs.
  - A separate policy (`infra/iam/credentials-admin-policy.json`) already lets an administrator, or root, create and manage the limited user's credentials; the command can build on it.
  - The admin who runs the command needs `iam:CreateUser`, `iam:GetUser`, `iam:AttachUserPolicy`, `iam:CreateAccessKey`, `iam:CreateLoginProfile` and `iam:GetLoginProfile` (plus `iam:UpdateLoginProfile` for resets). Keep these out of `deploy-policy.json`, because they would let the deploy user create credentials for itself and others.
- [ ] **Externalize shared settings in one place.** `project_name`, `tags`, `aws_region` and similar values are repeated in `infra/bootstrap`, `environments/dev` and `environments/prod` (each with its own tfvars and defaults), plus the state bucket and region again in `backend.hcl`. Define them once (for example a single root tfvars or config file read by every stack and by the Makefile) so a rename or region change is one edit.
- [ ] **Make bucket names globally unique by construction.** Bucket names are stated explicitly in tfvars (`state_bucket_name`, `site_bucket_name`) and `scripts/setup.sh` suggests `<project>-...` defaults, but nothing checks that a name is free. Add a pre-flight check (`aws s3api head-bucket`) to the wizard and consider adding the account ID to the suggested names.

- [ ] **Observability.** No alarms on Lambda errors, API 5xx or SES bounces/complaints, and no SNS topic. The handler returns 503 on SES failure without logging the cause, so lost messages cannot be diagnosed. Add structured logging on every non-200 path, API Gateway access logs, CloudWatch alarms and an SNS notification.
- [ ] **Email deliverability.** SES uses an *email* identity, so there is no DKIM/SPF/DMARC under your domain, and From equals To. Move to a domain identity with DKIM and DMARC records; confirm the SES sandbox/production status.
- [ ] **CloudFront hardening.**
  - Add a response-headers policy (HSTS, CSP that allows Google reCAPTCHA, X-Frame-Options, Referrer-Policy).
  - Replace legacy `forwarded_values` with cache and origin-request policies.
  - Stop forwarding `Authorization` to the API origin.
  - Enable access logging.
  - Add the directory-index function to `/photos/*`.
- [ ] **State and bootstrap protection.**
  - Bootstrap state is local and not backed up.
  - Add `prevent_destroy` on the state bucket and the site bucket.
  - Add a TLS-only bucket policy, a lifecycle rule for old state versions, and access logging on the state bucket.
- [ ] **Unify dev and prod.** `environments/dev/main.tf` is a different, smaller composition with a local backend, so dev does not test what prod runs. Use one shared root or composition module driven by tfvars. Dev also has no budget.
- [ ] **Reproducible builds.** `.terraform.lock.hcl` is gitignored, yet `infra/bootstrap/.terraform.lock.hcl` is tracked. Commit all lock files. Add an upper bound to `required_version` and plan the move to AWS provider 6.x.
- [ ] **Budget thresholds.** The estimate is $0–2/month, but the first alert fires at $5 (10% of $50) and only on `ACTUAL`. Lower the first alert to about $1–2, add a `FORECASTED` alert, enable Cost Anomaly Detection (free) and add a budget for dev.
- [ ] **Account hygiene.** Document or provision CloudTrail (first management trail is free), root MFA / IAM Identity Center, and a least-privilege policy for the human or CI role that runs `tofu`.

## Done in this iteration

- Bucket names are explicit config: `state_bucket_name` (bootstrap) and `site_bucket_name` (dev, prod) in tfvars, validated as S3 names; `backend.hcl`, the wizard and the IAM policy templates (`STATE_BUCKET`, `SITE_BUCKET`, `DEV_SITE_BUCKET`) use the same values.
- DynamoDB removed from the project: state locking is S3-native (`use_lockfile`), the lock table is gone from bootstrap, docs and IAM policies.
- Root `Makefile` with `bootstrap`, `dev|prod-apply`, `dev|prod-destroy`, `dev|prod-sync`, `help`; `infra/Makefile` removed. Site bucket uses `force_destroy` so destroy works with synced content.
  - Follow-ups if CI needs them: `fmt-check`/`validate` targets.
- `s3-static-sync` now uses `aws s3 sync` (no per-file state) and invalidates CloudFront; dotfiles are skipped at any depth.
- Env var `TF_VAR_recaptcha_secret_key_env` takes precedence over `terraform.tfvars`.
- CloudFront sends a secret `X-Origin-Verify` header and the Lambda rejects requests without it (direct `execute-api` hits are blocked).
- Contact route throttled to 1 request/minute.
- `website/404.html` with client-side debug info; contact form added to `website/index.html`.
