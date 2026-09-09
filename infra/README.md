# Infrastructure — single domain, path routing

One custom domain, one CloudFront distribution, one S3 bucket with prefixes:

| Path | Origin |
|---|---|
| `/` | S3 site root |
| `/admin/*` | S3 `admin/` (SPA fallback) |
| `/photos/*` | S3 `photos/` |
| `/api/*` | API Gateway (CloudFront function strips `/api` prefix) |

No subdomains. No ALB. ACM certificate in **us-east-1** for CloudFront.

## Prerequisites

- OpenTofu >= 1.6, AWS CLI configured
- IAM permissions boundary on Lambda roles (if your org requires it)
- DNS managed at your registrar (external to Route 53)

## Bootstrap (remote state)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
tofu init && tofu apply
```

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

Edit `terraform.tfvars`: domain, emails, IAM boundary, tags.

Edit `backend.hcl` with bucket/table names from bootstrap outputs.

```bash
tofu init -reconfigure -backend-config=backend.hcl
```

### 1. ACM certificate (Phase A — DNS validation)

```bash
tofu apply -target=module.acm.aws_acm_certificate.this
tofu output acm_dns_validation_records
```

Add the **validation CNAME** at your registrar (one per name — apex and `www` after this change):

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

CloudFront creation takes **5–15 minutes**. With `acm_wait_for_validation = true`, the distribution gets your domain alias and ACM cert.

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

### 6. Lambda invalidations

After CloudFront exists:

```hcl
cloudfront_distribution_id = "<from output>"
```

```bash
tofu apply -target=module.lambda_publish
```

## Post-deploy

### Cognito admin user

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
```

Cognito callback URLs (configured in Terraform): `https://<domain>/admin/callback`, logout `https://<domain>/admin`.

### SES

Verify the inbox for the SES verification email. Contact form Lambda returns 501 until implemented.

### Admin UI

Vite `base: '/admin/'`. Build and deploy:

```bash
cd admin-ui && npm run build
aws s3 sync dist/ s3://$BUCKET/admin/
```

## Makefile targets

```bash
make bootstrap-apply    # state bucket + lock table
make prod-init-first    # copy backend.hcl.example → backend.hcl, init
make prod-init          # init with existing backend.hcl
make prod-apply
make dev-destroy        # tear down dev when not actively developing
make fmt validate
```

`dev` provisions its own CloudFront distribution, Cognito pool, DynamoDB table, and S3 bucket alongside `prod`. These are usage-based and cost ~$0 idle, but run `make dev-destroy` when you're done with a session to avoid leaving duplicate baseline resources around.

## Outputs

| Output | Use |
|---|---|
| `cloudfront_domain_name` | Registrar CNAME / ALIAS target |
| `cloudfront_distribution_id` | `terraform.tfvars` for publish Lambda |
| `site_bucket_name` | `aws s3 sync` target |
| `acm_dns_validation_records` | Phase A DNS |
| `cognito_*` | Admin SPA env |
| `dns_records_manual` | Combined DNS helper |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Output "cloudfront_domain_name" not found` | CloudFront not applied or outputs stale | Complete `tofu apply`; distribution must exist in state |
| CloudFront 403, `server: AmazonS3` | Empty bucket or missing `index.html` | Add files under `website/` and `tofu apply` |
| `InvalidViewerCertificate` | Cert not validated before alias attach | Phase A/B ACM flow; keep `acm_wait_for_validation = false` until DNS validates |
| `dig` empty after apex CNAME | Registrar rejected CNAME (MX conflict) | Use ALIAS or contact registrar |
| Site works on `*.cloudfront.net` but not custom domain | Alias not attached | `acm_wait_for_validation = true` + re-apply |
| `www` resolves to nothing | `www` CNAME → apex with empty apex | Point `www` → CloudFront directly |

## Configuration reference (no hardcoded secrets in repo)

| Setting | Where |
|---|---|
| Domain, emails, tags | `terraform.tfvars` (gitignored) |
| State backend bucket/table | `backend.hcl` (gitignored) |
| IAM permissions boundary | `terraform.tfvars` |
| `acm_wait_for_validation` | `terraform.tfvars` — controls CloudFront alias + cert |
| `cloudfront_distribution_id` | `terraform.tfvars` — set after first apply |

Committed defaults (`project_name`, `aws_region`) are intentional; override in `terraform.tfvars`.

## Modules

| Module | Purpose |
|---|---|
| `acm` | us-east-1 cert, optional validation wait |
| `cloudfront-app` | Unified distribution, OAC bucket policy, CF functions |
| `s3-bucket` | Single bucket + OAC |
| `lambda` | Publish + contact handlers |
| `api` | HTTP API (no custom domain — reached via CloudFront) |
| `cognito` | Admin user pool |
| `dynamodb` | Metadata table |
| `ses-email` | Single verified email |

Legacy unused: `cloudfront/`, `dns/`, `ses/` (superseded by `cloudfront-app`, external DNS, `ses-email`).
