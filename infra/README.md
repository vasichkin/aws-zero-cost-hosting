# Infrastructure — single domain, path routing

One custom domain, one CloudFront distribution, one S3 bucket with prefixes:

| Path | Origin |
|---|---|
| `/` (default) | S3 site root — CloudFront function rewrites `/about/` and `/about` to `/about/index.html` |
| `/admin*` | S3 `admin/` (SPA fallback to `/admin/index.html`) |
| `/photos/*` | S3 `photos/` (cached up to 1 year) |
| `/api/*` | API Gateway (CloudFront function strips `/api` prefix, no caching) |

Missing objects are served as **404** with `/404.html` (CloudFront rewrites S3's 403 to 404). `website/` has no `404.html` yet, so CloudFront cannot fetch the error page and returns a bare error; add one.

No subdomains (except `www`). No ALB. ACM certificate in **us-east-1** for CloudFront.

## Prerequisites

- OpenTofu >= 1.6, AWS CLI configured
- IAM permissions boundary on Lambda roles (if your org requires it)
- DNS managed at your registrar (external to Route 53)
- Google reCAPTCHA v3 site key (in the website) and secret key (for the contact Lambda)

## Regions

Code defaults to **eu-west-3**; the current deployment uses **eu-north-1** (set via `aws_region` in `terraform.tfvars` and `region` in `backend.hcl`). ACM is always in us-east-1.

## Bootstrap (remote state)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
tofu init && tofu apply
```

Bootstrap uses local state (`infra/bootstrap/terraform.tfstate`) — back it up, don't commit it.

Record outputs:

```bash
tofu output -raw state_bucket_name    # e.g. minimal-aws-tofu-state
tofu output -raw lock_table_name      # e.g. minimal-aws-tofu-lock
```

## Prod deploy sequence

### 0. Configure

```bash
cd infra/environments/prod
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

Edit `terraform.tfvars`: domain, `ses_email`, `admin_email`, IAM boundary, tags. Optional: `recaptcha_min_score` (default 0.5), `enable_dynamodb_pitr` (default true).

Provide the reCAPTCHA secret (required, sensitive) without writing it to the file:

```bash
export TF_VAR_recaptcha_secret_key="<google-recaptcha-v3-secret>"
```

Edit `backend.hcl` with bucket, table and region from bootstrap outputs.

```bash
tofu init -reconfigure -backend-config=backend.hcl
```

### 1. ACM certificate (Phase A — DNS validation)

```bash
tofu apply -target=module.acm.aws_acm_certificate.this
tofu output acm_dns_validation_records
```

Add the **validation CNAME** at your registrar (one per name — apex and `www`):

| Field | Value |
|---|---|
| Host | hash only (e.g. `_abc123…`) — omit domain if panel appends it |
| Type | CNAME |
| Target | value from output (no trailing dot) |

Verify:

```bash
dig +short CNAME _<hash>.<your-domain>
```

### 2. Wait for ACM validation

Set in `terraform.tfvars`:

```hcl
acm_wait_for_validation = true
```

```bash
tofu apply -target=module.acm
```

Cert status must be **ISSUED** (check: `aws acm list-certificates --region us-east-1`).

### 3. Full stack

```bash
tofu apply
```

CloudFront creation takes **5–15 minutes**. With `acm_wait_for_validation = true`, the distribution gets your domain aliases (apex + `www`) and ACM cert.

This also creates the monthly AWS Budget (see [Cost alerts](#cost-alerts)).

### 4. Website content

Files in `website/` are uploaded automatically on `tofu apply` (module `s3-static-sync`). After changing HTML/CSS/assets, run apply again to sync.

```bash
# verify upload
tofu output site_bucket_name
aws s3 ls s3://$(tofu output -raw site_bucket_name)/
```

Test via CloudFront default domain:

```bash
CF=$(tofu output -raw cloudfront_domain_name)
curl -I "https://$CF/"
# expect 200 after upload
```

### 5. Root domain DNS (Phase B)

```bash
tofu output -raw cloudfront_domain_name
# e.g. d111111abcdef8.cloudfront.net
```

Point apex and/or `www` at CloudFront.

| Host | Type | Target |
|---|---|---|
| `www` | CNAME | `d111111abcdef8.cloudfront.net` (from output) |
| `@` | ALIAS/CNAME | same target — often blocked when MX exists |

**Apex CNAME limitation:** RFC DNS disallows CNAME at `@` when MX (mail) records exist on the same name. Many registrars silently reject apex CNAME if Google Workspace / Gmail MX is configured.

**Practical setup at bestname:** CNAME `www` → CloudFront, then use registrar **domain redirect** for apex → `https://www.<domain>/`.

Options:

1. **ALIAS / ANAME / CNAME flattening** — if your registrar supports it, point `@` → CloudFront domain
2. **Registrar support** — ask how to map apex to CloudFront while keeping MX
3. **`www` subdomain** — add `www` CNAME at registrar (supported); redirect apex → www via registrar if apex CNAME is blocked
4. **External DNS** — Route 53 or Cloudflare with ALIAS at apex

Verify authoritative DNS (replace NS with yours):

```bash
dig @ns1.example.com your-domain.com CNAME +short
dig +short your-domain.com A
```

Do **not** point `www` → apex if apex has no records (creates a dead loop).

## Post-deploy

### Cognito admin user

The pool and an `admins` group are created for the admin project (separate, TBD). Nothing in this stack checks group membership yet.

```bash
POOL=$(tofu output -raw cognito_user_pool_id)
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL" \
  --username "<admin-email>" \
  --user-attributes Name=email,Value=<admin-email> Name=email_verified,Value=true \
  --message-action SUPPRESS
aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL" \
  --username "<admin-email>" \
  --password "<temp-password>" \
  --permanent
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$POOL" \
  --username "<admin-email>" \
  --group-name admins
```

Cognito callback URLs (configured in Terraform): `https://<domain>/admin/callback` and `https://www.<domain>/admin/callback`; logout `https://<domain>/admin` and `https://www.<domain>/admin`.

### SES

Verify the inbox for the SES verification email (`tofu output ses_verification_note`). The contact Lambda sends from and to `ses_email`. While the account is in the SES sandbox it can only send to verified addresses, which is enough here because sender and recipient are the same verified address.

### Admin UI

Separate project (TBD). It is expected to build with Vite `base: '/admin/'` and sync to `s3://<site_bucket>/admin/`. Admin API routes should attach to this stack's HTTP API using the Cognito JWT authorizer (`module.api` output `authorizer_id`).

## API routes

| CloudFront path | API Gateway route | Auth | Target |
|---|---|---|---|
| `POST /api/contact` | `POST /contact` | none; throttled burst 10 / 5 rps; reCAPTCHA v3 + honeypot in handler | `lambda/contact` (prod only) |

Request/response contract: see [Contact API](../README.md#contact-api).

## Cost alerts

Prod creates `aws_budgets_budget.monthly_cost`: $50/month cost budget with ACTUAL-spend email alerts to `admin_email` at 10% (~$5), 40% (~$20) and 100% ($50).

## Makefile targets

```bash
make bootstrap-init | bootstrap-plan | bootstrap-apply   # state bucket + lock table
make dev-init | dev-plan | dev-apply | dev-destroy
make prod-init-first    # copy backend.hcl.example → backend.hcl, init
make prod-init          # init with existing backend.hcl
make prod-plan | prod-apply
make fmt validate
```

`make prod-init` runs `tofu init -backend-config=backend.hcl` without `-reconfigure`; add it manually when switching backends.

`dev` provisions its own CloudFront distribution, Cognito pool, DynamoDB table (PITR off), S3 bucket and HTTP API (no contact route, no SES, no budget; CORS for `http://localhost:5173`) alongside `prod`. These are usage-based and cost ~$0 idle, but run `make dev-destroy` when you're done with a session to avoid leaving duplicate baseline resources around.

## Outputs

| Output | Use |
|---|---|
| `site_url`, `www_url` | Public site URLs (apex / `www`) |
| `admin_url`, `photos_url`, `api_url` | Path-routed URLs on the domain |
| `cloudfront_domain_name` | Registrar CNAME / ALIAS target |
| `cloudfront_distribution_id` | Manual invalidations (`aws cloudfront create-invalidation`) |
| `site_bucket_name` | `aws s3 sync` target |
| `bucket_layout` | S3 prefixes (`/`, `admin/`, `photos/`) |
| `acm_dns_validation_records` | Phase A DNS |
| `cognito_user_pool_id`, `cognito_admin_client_id` | Admin SPA env |
| `admin_email` | Address for the Cognito admin user and budget alerts |
| `ses_verification_note` | SES verification reminder |
| `dns_records_manual` | Combined DNS helper |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Output "cloudfront_domain_name" not found` | CloudFront not applied or outputs stale | Complete `tofu apply`; distribution must exist in state |
| CloudFront 403/404 on `/` | Empty bucket or missing `index.html` (and no `404.html`) | Add files under `website/` and `tofu apply` |
| `InvalidViewerCertificate` | Cert not validated before alias attach | Phase A/B ACM flow; keep `acm_wait_for_validation = false` until DNS validates |
| `dig` empty after apex CNAME | Registrar rejected CNAME (MX conflict) | Use ALIAS or contact registrar |
| Site works on `*.cloudfront.net` but not custom domain | Alias not attached | `acm_wait_for_validation = true` + re-apply |
| `www` resolves to nothing | `www` CNAME → apex with empty apex | Point `www` → CloudFront directly |
| `tofu plan` prompts for `recaptcha_secret_key` | Required variable not set | `export TF_VAR_recaptcha_secret_key=...` |
| Contact form returns 500 `CONFIGURATION_ERROR` | reCAPTCHA secret/hostnames or `ALLOWED_ORIGINS` empty | Check the Lambda environment set by `module.lambda_contact` |

## Configuration reference (no hardcoded secrets in repo)

| Setting | Where |
|---|---|
| `domain_name`, `ses_email`, `admin_email`, tags | `terraform.tfvars` (gitignored) |
| `recaptcha_secret_key` (required, sensitive) | `TF_VAR_recaptcha_secret_key` env var (or `terraform.tfvars`) |
| `recaptcha_min_score` | `terraform.tfvars` — default 0.5 |
| `enable_dynamodb_pitr` | `terraform.tfvars` — default true |
| State backend bucket/table/region | `backend.hcl` (gitignored; template `backend.hcl.example`) |
| IAM permissions boundary | `terraform.tfvars` |
| `acm_wait_for_validation` | `terraform.tfvars` — controls CloudFront alias + cert |

Committed defaults (`project_name`, `aws_region`) are intentional; override in `terraform.tfvars`.

## Modules

| Module | Purpose |
|---|---|
| `acm` | us-east-1 cert (apex + `www`), optional validation wait |
| `cloudfront-app` | Unified distribution, OAC bucket policy, 3 CF functions (directory index, admin SPA fallback, API prefix strip), 403/404 → `/404.html` |
| `s3-bucket` | Single bucket + OAC, SSE-S3, versioning with 30-day noncurrent-version expiry, optional CORS |
| `s3-static-sync` | Uploads `website/` to the bucket on apply (content types, `Cache-Control: public, max-age=3600`) |
| `lambda` | Generic Python 3.12 ARM64 function + IAM role + log group (14-day retention); used for the contact handler |
| `api` | HTTP API, Cognito JWT authorizer, `POST /contact` with throttling (no custom domain — reached via CloudFront) |
| `cognito` | Admin user pool, SPA client, `admins` group |
| `dynamodb` | Metadata table (on-demand, PK/SK, optional PITR) for the admin project |
| `ses-email` | Single verified email |
