# Project context

## Goal

Minimal-cost AWS hosting for a static public website with an authenticated admin publish pipeline. Application code (website, admin UI, Lambda logic) is developed separately; this repo holds infrastructure and handler placeholders.

## Architecture

- **Single domain** with path routing through one CloudFront distribution (`www` alias for DNS when apex CNAME is blocked)
- **Single S3 bucket** with prefixes: `/` (site), `/admin/`, `/photos/`
- **API** at `/api/*` → API Gateway → Lambda (CloudFront function strips prefix)
- **Cognito** for admin authentication
- **DynamoDB** for content metadata
- **SES** (prod) for contact form email
- **External DNS** at registrar — no Route 53 hosted zone in this stack

## Target state

| Component | Status |
|---|---|
| Bootstrap (S3 state + DynamoDB lock) | Deployed |
| Prod stack (CF, S3, Lambda, API, Cognito, DynamoDB, SES, ACM) | Deployed |
| Custom domain on CloudFront | Requires `acm_wait_for_validation = true` + DNS |
| Apex DNS | Blocked if registrar rejects CNAME with MX — use ALIAS |
| Website content in S3 | Auto-sync on `tofu apply` via `website_sync` |
| Lambda handlers | Placeholders (501) |
| Admin UI | Placeholder |

## Key decisions

- **No service subdomains** — admin/API/photos use paths, not separate hostnames (except `www` for DNS)
- **No ALB** — CloudFront is the public entry point
- **ACM in us-east-1** — CloudFront requirement
- **`acm_wait_for_validation` flag** — two-phase deploy: cert first without alias, then attach domain after validation
- **Permissions boundary** — optional variable for orgs that require it on Lambda roles
- **Backend config externalized** — `backend.hcl` gitignored; names derived from bootstrap `project_name`

## Operational notes

- CloudFront distribution creation: 5–15 min
- Empty S3 → CloudFront 403 (not a misconfiguration)
- After first CloudFront apply, set `cloudfront_distribution_id` in tfvars for publish Lambda invalidations
- `.terraform.lock.hcl` is committed; `terraform.tfvars` and `backend.hcl` are not

## Related docs

- [README.md](../README.md) — repo overview
- [infra/README.md](../infra/README.md) — deploy runbook
- [DEPLOYMENT.md](DEPLOYMENT.md) — mermaid architecture & deploy diagrams
- [budget.md](budget.md) — cost of ownership & free tier
