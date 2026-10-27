# Deployment architecture

Mermaid diagrams for the minimal-aws hosting stack. The admin panel is TBD and not shown.

Regions: code defaults to **eu-west-3**; the current deployment runs in **eu-north-1**. Diagrams say "primary region" for either. ACM is always in **us-east-1**.

## Runtime architecture

```mermaid
flowchart TB
  subgraph Internet
    User[Browser / visitor]
  end

  subgraph DNS["Registrar DNS (external)"]
    Apex["apex domain"]
    WWW["www CNAME"]
    ACMVal["ACM validation CNAMEs"]
  end

  Google["Google reCAPTCHA v3<br/>(external)"]

  subgraph AWS["AWS — primary region (+ us-east-1 for ACM)"]
    subgraph Edge["CloudFront (global edge)"]
      CF["Distribution<br/>aliases: apex + www"]
      FnIndex["CF function: directory index"]
      FnAPI["CF function: strip /api prefix"]
    end

    subgraph Storage["S3 — single bucket (versioned)"]
      S3Root["/ index.html, assets"]
      S3Photos["/photos/ images"]
    end

    subgraph API["HTTP API"]
      APIGW["API Gateway v2<br/>POST /contact (throttled)"]
      LContact["Lambda contact"]
    end

    SES["SES verified email"]
    Budget["AWS Budget<br/>$50/month alerts"]
    Logs["CloudWatch Logs<br/>14-day retention"]

    subgraph Cert["us-east-1"]
      ACM["ACM certificate<br/>apex + www SANs"]
    end

    subgraph State["OpenTofu state (bootstrap)"]
      StateS3["S3 state bucket"]
      StateLock["DynamoDB lock table"]
    end
  end

  subgraph Repo["This repo"]
    Website["website/"]
    Tofu["OpenTofu apply"]
  end

  User --> Apex
  User --> WWW
  Apex --> CF
  WWW --> CF
  ACMVal -.-> ACM

  CF -->|"/"| FnIndex --> S3Root
  CF -->|"/photos/*"| S3Photos
  CF -->|"/api/*"| FnAPI --> APIGW

  APIGW --> LContact
  LContact --> Google
  LContact --> SES
  LContact --> Logs

  ACM --> CF
  Tofu --> Website
  Tofu -->|website_sync| S3Root
  Tofu --> StateS3
  Tofu --> StateLock
  Tofu --> Budget
```

## Path routing (CloudFront)

```mermaid
flowchart LR
  CF[CloudFront] -->|default /| Idx["directory index"] --> S3Site["S3 /"]
  CF -->|/photos/*| S3Photos["S3 /photos/"]
  CF -->|/api/*| Fn["strip /api"] --> APIGW["API Gateway"]
```

## Deployment sequence

```mermaid
flowchart TD
  Start([Start]) --> Boot

  subgraph Phase0["Phase 0 — Bootstrap (once)"]
    Boot["infra/bootstrap<br/>tofu apply (local state)"]
    Boot --> StateOut["Outputs: state bucket + lock table"]
  end

  StateOut --> Config

  subgraph Phase1["Phase 1 — Configure prod"]
    Config["Copy terraform.tfvars + backend.hcl from *.example"]
    Secret["Set recaptcha_secret_key in terraform.tfvars"]
    Init["tofu init -reconfigure -backend-config=backend.hcl"]
    Config --> Secret --> Init
  end

  Init --> ACM1

  subgraph Phase2["Phase 2 — ACM cert"]
    ACM1["tofu apply -target=module.acm.aws_acm_certificate.this<br/>creates cert (apex + www)"]
    DNSVal["Add validation CNAMEs at registrar"]
    ACM1 --> DNSVal
    DNSVal --> WaitVal["Set acm_wait_for_validation = true"]
    WaitVal --> ACM2["tofu apply -target=module.acm<br/>cert ISSUED"]
  end

  ACM2 --> Full

  subgraph Phase3["Phase 3 — Full stack"]
    Full["tofu apply"]
    Full --> CFDeploy["CloudFront ~5–15 min<br/>aliases + ACM attached"]
    Full --> WebsiteUp["website/ → S3 via website_sync"]
    Full --> Stack["Contact Lambda, API, SES, Budget"]
  end

  CFDeploy --> DNSLive

  subgraph Phase4["Phase 4 — Live DNS"]
    DNSLive["www CNAME → *.cloudfront.net"]
    DNSApex["apex redirect → www (if CNAME blocked)"]
    DNSLive --> Test["curl https://www.domain/"]
    DNSApex --> Test
  end

  Test --> Post

  subgraph Phase5["Phase 5 — Post-deploy"]
    Post["Post-deploy tasks"]
    Post --> SESVerify["Verify SES email"]
  end

  SESVerify --> Done([Site live])
```

## OpenTofu module dependency graph

```mermaid
flowchart BT
  ACM[module.acm]
  Bucket[module.site_bucket]
  Sync[module.website_sync]
  SES[module.ses]
  LContact[module.lambda_contact]
  API[module.api]
  CF[module.cloudfront]
  Budget[aws_budgets_budget.monthly_cost]

  Bucket --> Sync
  SES --> LContact
  LContact --> API
  API --> CF
  Bucket --> CF
  ACM --> CF
```

`aws_budgets_budget.monthly_cost` has no dependencies on other modules. `module.cloudfront` also has an explicit `depends_on = [module.api]`.

## Regions

```mermaid
flowchart LR
  subgraph primary["Primary region (eu-west-3 default, eu-north-1 deployed)"]
    S3[S3 site bucket]
    Lambda[Lambda contact]
    APIGW[API Gateway]
    SES[SES]
    State[OpenTofu state]
  end

  subgraph us-east-1["us-east-1"]
    ACM[ACM certificate]
  end

  subgraph Global["Global"]
    CF[CloudFront]
    Budget[AWS Budgets]
  end

  ACM --> CF
  S3 --> CF
  APIGW --> CF
```

## Related docs

- [CONTEXT.md](CONTEXT.md) — decisions and target state
- [../infra/README.md](../infra/README.md) — step-by-step runbook
