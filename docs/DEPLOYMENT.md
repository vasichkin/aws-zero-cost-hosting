# Deployment architecture

Mermaid diagrams for the minimal-aws hosting stack.

## Runtime architecture

```mermaid
flowchart TB
  subgraph Internet
    User[Browser / visitor]
    Admin[Admin browser]
  end

  subgraph DNS["Registrar DNS (external)"]
    Apex["apex domain"]
    WWW["www CNAME"]
    ACMVal["ACM validation CNAMEs"]
  end

  subgraph AWS["AWS — eu-west-3 (+ us-east-1 for ACM)"]
    subgraph Edge["CloudFront (global edge)"]
      CF["Distribution<br/>aliases: apex + www"]
      FnAPI["CF function: strip /api prefix"]
      FnAdmin["CF function: admin SPA fallback"]
    end

    subgraph Storage["S3 — single bucket"]
      S3Root["/ index.html, assets"]
      S3Admin["/admin/ SPA"]
      S3Photos["/photos/ images"]
    end

    subgraph API["HTTP API"]
      APIGW["API Gateway v2"]
      LPub["Lambda publish"]
      LContact["Lambda contact"]
    end

    subgraph Auth["Auth & data"]
      Cognito["Cognito user pool"]
      DDB["DynamoDB metadata"]
      SES["SES verified email"]
    end

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
    AdminUI["admin-ui/ dist"]
    Tofu["OpenTofu apply"]
  end

  User --> Apex
  User --> WWW
  Admin --> WWW
  Apex --> CF
  WWW --> CF
  ACMVal -.-> ACM

  CF -->|"/"| S3Root
  CF -->|"/admin*"| FnAdmin --> S3Admin
  CF -->|"/photos/*"| S3Photos
  CF -->|"/api/*"| FnAPI --> APIGW

  APIGW --> LPub
  APIGW --> LContact
  LPub --> DDB
  LPub --> S3Root
  LPub --> S3Photos
  LPub --> CF
  LContact --> SES
  APIGW --> Cognito
  Admin --> Cognito

  ACM --> CF
  Tofu --> Website
  Tofu -->|website_sync| S3Root
  AdminUI -.->|manual s3 sync| S3Admin
  Tofu --> StateS3
  Tofu --> StateLock
```

## Path routing (CloudFront)

```mermaid
flowchart LR
  CF[CloudFront] -->|default /| S3Site["S3 /"]
  CF -->|/admin*| S3Admin["S3 /admin/"]
  CF -->|/photos/*| S3Photos["S3 /photos/"]
  CF -->|/api/*| Fn["strip /api"] --> APIGW["API Gateway"]
```

## Deployment sequence

```mermaid
flowchart TD
  Start([Start]) --> Boot

  subgraph Phase0["Phase 0 — Bootstrap (once)"]
    Boot["infra/bootstrap<br/>tofu apply"]
    Boot --> StateOut["Outputs: state bucket + lock table"]
  end

  StateOut --> Config

  subgraph Phase1["Phase 1 — Configure prod"]
    Config["Copy terraform.tfvars + backend.hcl"]
    Init["tofu init -backend-config=backend.hcl"]
    Config --> Init
  end

  Init --> ACM1

  subgraph Phase2["Phase 2 — ACM cert"]
    ACM1["tofu apply -target=module.acm<br/>creates cert (apex + www)"]
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
    Full --> Stack["Lambda, API, Cognito, DynamoDB, SES"]
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
    Post["Set cloudfront_distribution_id in tfvars"]
    Post --> LambdaInv["tofu apply -target=module.lambda_publish"]
    Post --> CognitoUser["Create Cognito admin user"]
    Post --> AdminSync["Build admin-ui → s3 sync /admin/"]
    Post --> SESVerify["Verify SES email"]
  end

  LambdaInv --> Done([Site live])
  CognitoUser --> Done
  AdminSync --> Done
  SESVerify --> Done
```

## OpenTofu module dependency graph

```mermaid
flowchart BT
  ACM[module.acm]
  Bucket[module.site_bucket]
  Sync[module.website_sync]
  DDB[module.metadata_table]
  Cognito[module.cognito]
  SES[module.ses]
  LPub[module.lambda_publish]
  LContact[module.lambda_contact]
  API[module.api]
  CF[module.cloudfront]

  Bucket --> Sync
  Bucket --> LPub
  DDB --> LPub
  SES --> LContact
  Cognito --> API
  LPub --> API
  LContact --> API
  API --> CF
  Bucket --> CF
  ACM --> CF
```

## Regions

```mermaid
flowchart LR
  subgraph eu-west-3["eu-west-3 (primary)"]
    S3[S3 site bucket]
    DDB[DynamoDB]
    Lambda[Lambda functions]
    APIGW[API Gateway]
    Cognito[Cognito]
    SES[SES]
    State[OpenTofu state]
  end

  subgraph us-east-1["us-east-1"]
    ACM[ACM certificate]
  end

  subgraph Global["Global"]
    CF[CloudFront]
  end

  ACM --> CF
  S3 --> CF
  APIGW --> CF
```

## Related docs

- [CONTEXT.md](CONTEXT.md) — decisions and target state
- [../infra/README.md](../infra/README.md) — step-by-step runbook
