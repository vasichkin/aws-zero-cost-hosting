# Minimal AWS hosting

### This project is about creating hosting with zero cost on AWS infrastructure.

Minimal-TCO static site on AWS: one S3 bucket, one CloudFront distribution, path-based routing, Cognito admin auth, Lambda API, DynamoDB metadata.

Website and admin UI live in separate folders and deploy independently of this repo's OpenTofu stack.

## Layout

```
infra/           OpenTofu — bootstrap, modules, dev/prod environments
lambda/          Placeholder Lambda handlers (publish, contact)
website/         Static public site (sync to S3)
admin-ui/        Admin SPA (build + sync to S3 admin/ prefix)
docs/            Project context
```

## Quick start

1. **Bootstrap remote state** (once per AWS account):

   ```bash
   cd infra/bootstrap
   cp terraform.tfvars.example terraform.tfvars   # edit tags/region
   tofu init && tofu apply
   tofu output   # note state_bucket_name, lock_table_name
   ```

2. **Prod infra**:

   ```bash
   cd infra/environments/prod
   cp terraform.tfvars.example terraform.tfvars   # edit domain, emails, IAM boundary
   cp backend.hcl.example backend.hcl             # set bucket/table from bootstrap outputs
   tofu init -reconfigure -backend-config=backend.hcl
   tofu apply
   ```

3. **Upload site content** — automatic on `tofu apply` from `website/`; or manual `aws s3 sync` if preferred

4. **Full deployment guide** — see [infra/README.md](infra/README.md) (ACM, DNS, Cognito, SES).

## Environments

| | dev | prod |
|---|---|---|
| State | local | S3 remote (bootstrap) |
| Custom domain | no | yes (after ACM + DNS) |
| SES / contact form | no | yes |

## Configuration

All environment-specific values belong in **gitignored** files:

- `infra/environments/prod/terraform.tfvars`
- `infra/environments/prod/backend.hcl`
- `infra/bootstrap/terraform.tfvars`

Never commit account IDs, emails, domains, or ARNs — use the `*.example` templates.

See [docs/CONTEXT.md](docs/CONTEXT.md) for architecture and operational notes.

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for mermaid deployment diagrams.

See [docs/budget.md](docs/budget.md) for cost of ownership and free tier estimates.
