# Minimal AWS hosting

### This project is about creating hosting with zero cost on AWS infrastructure.

Minimal-TCO static site on AWS: one S3 bucket, one CloudFront distribution, path-based routing, a Lambda-backed contact form (reCAPTCHA v3 + SES), and AWS Budgets cost alerts.

The public website in `website/` is synced to S3 with `aws s3 sync` (CloudFront cache invalidated afterwards) by `tofu apply`; files are not stored in the OpenTofu state.

## Architecture

```mermaid
flowchart LR
  Visitor([Visitor browser])
  Owner([Site owner mailbox])
  DNS["Registrar DNS<br/>(external)"]
  Google["Google reCAPTCHA v3<br/>(external)"]

  subgraph AWS["AWS stack (OpenTofu)"]
    Stack["CloudFront + S3 site<br/>API Gateway + Lambda contact"]
    SES["SES"]
  end

  Visitor -->|"HTTPS apex / www"| DNS --> Stack
  Visitor -.->|"reCAPTCHA token"| Google
  Stack -->|"verify token"| Google
  Stack --> SES -->|"contact email"| Owner
```

- **One CloudFront distribution** is the single public entry point. Visitors reach it through the registrar's DNS (apex and `www`), and path routing sends each request to the right origin.
- **Static site:** `/` and `/photos/*` are served from one private, versioned S3 bucket through an origin access control. `website/` is synced to it with `aws s3 sync` on `tofu apply`, followed by a CloudFront invalidation.
- **Contact API:** `/api/*` goes to API Gateway and the `lambda/contact` function. It validates the request, checks the reCAPTCHA v3 token with Google, and sends the message through SES to the owner.

More diagrams:

- Deploy sequence, module dependencies and regions: [docs/INFRA.md](docs/INFRA.md)
- Contact handler request flow: [docs/API-CONTACT.md](docs/API-CONTACT.md)

## Layout

```
infra/           OpenTofu — bootstrap, modules, dev/prod environments
lambda/contact/  Contact form handler (validation, reCAPTCHA v3, SES) + unit tests
website/         Static public site (aws s3 sync + CloudFront invalidation on tofu apply)
docs/            Project context, architecture diagrams, budget
```

## Quick start (happy path: nothing to live site)

Prerequisites: OpenTofu >= 1.7, AWS CLI with working credentials, a Google reCAPTCHA v3 key pair (site key + secret), access to your registrar's DNS. Run everything from the repository root.

```bash
# 1. Remote state (once per AWS account). Note the bucket/table names it prints.
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars   # edit tags/region
make bootstrap

# 2. Configure prod
cp infra/environments/prod/terraform.tfvars.example infra/environments/prod/terraform.tfvars   # domain, emails, IAM boundary, tags
cp infra/environments/prod/backend.hcl.example infra/environments/prod/backend.hcl             # bucket/table/region from step 1
export TF_VAR_recaptcha_secret_key_env="<recaptcha-v3-secret>"
# put the reCAPTCHA *site* key into website/index.html (replace CHANGE_ME in the recaptcha-site-key meta tag)

# 3. First apply: S3, CloudFront (default domain), API, Lambda, SES, budget, ACM certificate, website sync
make prod-apply

# 4. Custom domain: add the ACM validation CNAMEs at your registrar (from `tofu output acm_dns_validation_records`
#    in infra/environments/prod), set acm_wait_for_validation = true in terraform.tfvars, then apply again
make prod-apply
```

Then, once:
1. Click the SES verification link sent to `ses_email`.
2. Point `www` (and the apex, via ALIAS/ANAME or redirect) at `tofu output cloudfront_domain_name` at your registrar.
3. Open `https://<your-domain>/` and send a test message with the contact form.

Day-to-day:

| Command | What it does |
|---|---|
| `make prod-sync` | Publish `website/` now: `aws s3 sync` + CloudFront invalidation, no full apply |
| `make prod-apply` | Apply infrastructure changes (also syncs the website when its content changed) |
| `make dev-apply` / `dev-sync` / `dev-destroy` | The same for the dev environment (local state, CloudFront default domain) |
| `make prod-destroy` | Destroy prod (asks for confirmation; deletes the site bucket and its content) |

Add `ARGS=-auto-approve` to skip tofu's confirmation, for example `make dev-destroy ARGS=-auto-approve`. Details, DNS tables, troubleshooting and the deploy sequence diagram: [docs/INFRA.md](docs/INFRA.md).

## Environments

| | dev | prod |
|---|---|---|
| State | local | S3 remote (bootstrap) |
| Custom domain | no | yes (after ACM + DNS) |
| SES / contact form | no | yes |
| Budget alerts | no | yes ($50/month, alerts at ~$5 / $20 / $50) |

## Contact API

`POST /api/contact` — see [docs/API-CONTACT.md](docs/API-CONTACT.md) for the request/response contract and tests.

## Configuration

All environment-specific values belong in **gitignored** files:

- `infra/environments/prod/terraform.tfvars`
- `infra/environments/prod/backend.hcl`
- `infra/bootstrap/terraform.tfvars`
- `infra/bootstrap/terraform.tfstate` (bootstrap local state)

Never commit account IDs, emails, domains, ARNs or the reCAPTCHA secret — use the `*.example` templates.

See [docs/CONTEXT.md](docs/CONTEXT.md) for architecture and operational notes.

See [docs/INFRA.md](docs/INFRA.md) for the deployment runbook and infrastructure details.

See [docs/API-CONTACT.md](docs/API-CONTACT.md) for the contact API contract.

See [docs/BUDGET.md](docs/BUDGET.md) for cost of ownership and free tier estimates.
