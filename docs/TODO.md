# TODO

Open work items from the DevOps review. Highest priority first.

## High

- [ ] **Distribution-wide error mapping hides API errors.** The `custom_error_response` blocks (403/404 → `/404.html`) in `infra/modules/cloudfront-app` apply to `/api/*` too, so the Lambda's 403 responses (`CAPTCHA_FAILED`, `ORIGIN_NOT_ALLOWED`, `FORBIDDEN`) reach the browser as the HTML 404 page. Serve the 404 page from a function or origin-response logic instead, or stop using 403/404 for API errors.
- [ ] **Move the reCAPTCHA secret to SSM Parameter Store (SecureString).** Today it is a Lambda env var and appears in plaintext in the tofu state. Pass only the parameter name to the Lambda, grant `ssm:GetParameter` on that one parameter, and read it at cold start. Until then, set it via `terraform.tfvars` or `TF_VAR_recaptcha_secret_key_env`.
- [ ] **CI/CD pipeline.** Nothing runs `tofu fmt -check`, `validate`, tflint, checkov/trivy or the Lambda tests, and deploys happen from a laptop. Add a pipeline using OIDC to a least-privilege deploy role, `plan -out` then apply that exact plan, and a manual approval for prod.
- [ ] **Run content deploys from CI.** Content is now synced by `aws s3 sync` from `tofu apply`, so it is out of the state but still needs infra credentials. When CI exists, move the sync and invalidation into a separate job with a role limited to the site bucket and `cloudfront:CreateInvalidation`.
- [ ] **Global-only throttling.** The contact route is limited to 1 request/minute across all visitors, so one bot can lock out real users, and failed reCAPTCHA attempts also use the quota. Per-client limits need WAF (rate-based rule, paid). Also set Lambda reserved concurrency.

## Medium


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
  - Make the state bucket name globally unique (add the account ID).
- [ ] **Unify dev and prod.** `environments/dev/main.tf` is a different, smaller composition with a local backend, so dev does not test what prod runs. Use one shared root or composition module driven by tfvars. Dev also has no budget.
- [ ] **Reproducible builds.** `.terraform.lock.hcl` is gitignored, yet `infra/bootstrap/.terraform.lock.hcl` is tracked. Commit all lock files. Add an upper bound to `required_version` and plan the move to AWS provider 6.x.
- [ ] **Budget thresholds.** The estimate is $0–2/month, but the first alert fires at $5 (10% of $50) and only on `ACTUAL`. Lower the first alert to about $1–2, add a `FORECASTED` alert, enable Cost Anomaly Detection (free) and add a budget for dev.
- [ ] **Account hygiene.** Document or provision CloudTrail (first management trail is free), root MFA / IAM Identity Center, and a least-privilege policy for the human or CI role that runs `tofu`.

## Done in this iteration

- DynamoDB removed from the project: state locking is S3-native (`use_lockfile`), the lock table is gone from bootstrap, docs and IAM policies.
- Root `Makefile` with `bootstrap`, `dev|prod-apply`, `dev|prod-destroy`, `dev|prod-sync`, `help`; `infra/Makefile` removed. Site bucket uses `force_destroy` so destroy works with synced content.
  - Follow-ups if CI needs them: `fmt-check`/`validate` targets.
- `s3-static-sync` now uses `aws s3 sync` (no per-file state) and invalidates CloudFront; dotfiles are skipped at any depth.
- Env var `TF_VAR_recaptcha_secret_key_env` takes precedence over `terraform.tfvars`.
- CloudFront sends a secret `X-Origin-Verify` header and the Lambda rejects requests without it (direct `execute-api` hits are blocked).
- Contact route throttled to 1 request/minute.
- `website/404.html` with client-side debug info; contact form added to `website/index.html`.
