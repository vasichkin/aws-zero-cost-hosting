# Minimal AWS hosting

### This project is about creating hosting with zero cost on AWS infrastructure.

Minimal-TCO static site on AWS: one S3 bucket, one CloudFront distribution, path-based routing, a Lambda-backed contact form (reCAPTCHA v3 + SES), Cognito and DynamoDB reserved for the admin side, and AWS Budgets cost alerts.

The public website in `website/` is synced to S3 by `tofu apply`. The admin UI and its API handlers are a separate project (TBD) and deploy independently of this repo.

## Layout

```
infra/           OpenTofu — bootstrap, modules, dev/prod environments
lambda/contact/  Contact form handler (validation, reCAPTCHA v3, SES) + unit tests
website/         Static public site (synced to S3 on tofu apply)
docs/            Project context, diagrams, budget
```

## Quick start

1. **Bootstrap remote state** (once per AWS account):

   ```bash
   cd infra/bootstrap
   cp terraform.tfvars.example terraform.tfvars   # edit tags/region
   tofu init && tofu apply
   tofu output   # note state_bucket_name, lock_table_name
   ```

   Bootstrap keeps its own state **locally** in `infra/bootstrap/terraform.tfstate`. Back this file up and do not commit it.

2. **Prod infra**:

   ```bash
   cd infra/environments/prod
   cp terraform.tfvars.example terraform.tfvars   # edit domain, emails, IAM boundary, reCAPTCHA
   cp backend.hcl.example backend.hcl             # set bucket/table/region from bootstrap outputs
   export TF_VAR_recaptcha_secret_key="<google-recaptcha-v3-secret>"   # keeps the secret out of tfvars
   tofu init -reconfigure -backend-config=backend.hcl
   tofu apply
   ```

3. **Upload site content** — automatic on `tofu apply` from `website/`; or manual `aws s3 sync` if preferred.

4. **Full deployment guide** — see [infra/README.md](infra/README.md) (ACM, DNS, Cognito, SES).

## Environments

| | dev | prod |
|---|---|---|
| State | local | S3 remote (bootstrap) |
| Custom domain | no | yes (after ACM + DNS) |
| SES / contact form | no | yes |
| DynamoDB PITR | off | on (`enable_dynamodb_pitr`) |
| Budget alerts | no | yes ($50/month, alerts at ~$5 / $20 / $50) |

## Contact API

`POST /api/contact` (CloudFront strips `/api`, API Gateway route `POST /contact`, handler `lambda/contact/handler.py`). Public route, throttled to burst 10 / 5 requests per second.

Request: `Content-Type: application/json`, `Origin` must be one of the site origins (apex or `www`), body up to 20 KB:

| Field | Required | Rules |
|---|---|---|
| `name` | yes | ≤ 120 chars |
| `email` | yes | ≤ 254 chars, valid email |
| `phone` | no | ≤ 40 chars |
| `projectType` | yes | ≤ 80 chars |
| `message` | yes | ≤ 4,000 chars |
| `locale` | yes | `pl`, `en` or `uk` |
| `projectId` | no | ≤ 80 chars |
| `consent` | yes | must be `true` |
| `recaptchaToken` | yes | Google reCAPTCHA v3 token, action `contact`, score ≥ `recaptcha_min_score` (default 0.5) |
| `company`, `honeypot` | no | honeypot fields; must be empty |

The message is emailed via SES from and to `ses_email`, with `Reply-To` set to the sender.

Response: `{"ok": true}` on success, otherwise `{"ok": false, "error": {"code", "message"}}`:

| Status | Code |
|---|---|
| 400 | `INVALID_CONTENT_TYPE`, `PAYLOAD_TOO_LARGE`, `VALIDATION_ERROR`, `INVALID_REQUEST` (honeypot) |
| 403 | `ORIGIN_NOT_ALLOWED`, `CAPTCHA_FAILED` |
| 405 | `METHOD_NOT_ALLOWED` |
| 500 | `CONFIGURATION_ERROR` |
| 503 | `CAPTCHA_UNAVAILABLE`, `DELIVERY_FAILED` |

Run the tests with `cd lambda/contact && python -m unittest test_handler`.

## Configuration

All environment-specific values belong in **gitignored** files:

- `infra/environments/prod/terraform.tfvars`
- `infra/environments/prod/backend.hcl`
- `infra/bootstrap/terraform.tfvars`
- `infra/bootstrap/terraform.tfstate` (bootstrap local state)

Never commit account IDs, emails, domains, ARNs or the reCAPTCHA secret — use the `*.example` templates.

See [docs/CONTEXT.md](docs/CONTEXT.md) for architecture and operational notes.

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for mermaid deployment diagrams.

See [docs/budget.md](docs/budget.md) for cost of ownership and free tier estimates.
