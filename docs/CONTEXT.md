# Project context

## Goal

Minimal-cost AWS hosting for a static public website with a protected contact form. This repo holds infrastructure, the public website and the contact Lambda.
## Architecture

- **Single domain** with path routing through one CloudFront distribution (`www` alias for DNS when apex CNAME is blocked)
- **Single S3 bucket** with prefixes: `/` (site), `/photos/` — versioned, 30-day expiry for old versions
- **Two CloudFront functions**: directory index on `/` (`/about/` → `/about/index.html`), `/api` prefix strip on `/api/*`
- **API** at `/api/*` → API Gateway HTTP API → Lambda. Live route: `POST /api/contact` (public, throttled burst 10 / 5 rps)
- **Contact Lambda** (`lambda/contact`): JSON validation, honeypot, Google reCAPTCHA v3, SES email. See [lambda/contact/README.md](../lambda/contact/README.md)
- **SES** (prod) for contact form email
- **AWS Budgets** (prod): $50/month with email alerts at ~$5 / $20 / $50
- **CloudWatch Logs**: 14-day retention on Lambda log groups
- **External DNS** at registrar — no Route 53 hosted zone in this stack

## Regions

Code defaults to **eu-west-3**. The current deployment uses **eu-north-1** (`aws_region` in tfvars, `region` in `backend.hcl`). ACM is in **us-east-1**.

## Current state

| Component | Status |
|---|---|
| Bootstrap (S3 state + DynamoDB lock) | Deployed |
| Prod stack (CF, S3, Lambda, API, SES, ACM, Budget) | Deployed |
| Custom domain on CloudFront | Requires `acm_wait_for_validation = true` + DNS |
| Apex DNS | Blocked if registrar rejects CNAME with MX — use ALIAS |
| Website content in S3 | Auto-sync on `tofu apply` via `website_sync` |
| Contact Lambda | Implemented (validation + reCAPTCHA v3 + SES), unit-tested |
## Key decisions

- **No service subdomains** — API/photos use paths, not separate hostnames (except `www` for DNS)
- **No ALB** — CloudFront is the public entry point
- **ACM in us-east-1** — CloudFront requirement
- **`acm_wait_for_validation` flag** — two-phase deploy: cert first without alias, then attach domain after validation
- **Permissions boundary** — optional variable for orgs that require it on Lambda roles
- **Backend config externalized** — `backend.hcl` gitignored (template `backend.hcl.example`); names derived from bootstrap `project_name`
- **reCAPTCHA secret** — `recaptcha_secret_key` in gitignored `terraform.tfvars` (or `TF_VAR_recaptcha_secret_key` with the tfvars line removed); never committed

## Operational notes

- CloudFront distribution creation: 5–15 min
- Missing objects: CloudFront turns S3's 403 into a 404 served from `/404.html`. `website/` has no `404.html` yet, so add one
- Bootstrap state is local (`infra/bootstrap/terraform.tfstate`) — back it up
- `.gitignore` excludes `terraform.tfvars`, `backend.hcl`, `*.tfstate` and `.terraform.lock.hcl` (lock files are not committed)

## Related docs

- [README.md](../README.md) — repo overview and architecture
- [infra/README.md](../infra/README.md) — deploy runbook, deploy sequence, module dependencies
- [lambda/contact/README.md](../lambda/contact/README.md) — contact API contract and request flow
- [DEPLOYMENT.md](DEPLOYMENT.md) — request routing diagram, regions
- [BUDGET.md](BUDGET.md) — cost of ownership & free tier
