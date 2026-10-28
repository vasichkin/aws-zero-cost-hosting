.PHONY: bootstrap-init bootstrap-plan bootstrap-apply dev-init dev-plan dev-apply dev-sync dev-destroy prod-init prod-init-first prod-acm-cert prod-acm-validate prod-plan prod-apply prod-sync fmt validate

ENV_DEV  := environments/dev
ENV_PROD := environments/prod
BOOTSTRAP := bootstrap

bootstrap-init:
	cd $(BOOTSTRAP) && tofu init

bootstrap-plan:
	cd $(BOOTSTRAP) && tofu plan

bootstrap-apply:
	cd $(BOOTSTRAP) && tofu apply

dev-init:
	cd $(ENV_DEV) && tofu init

dev-plan:
	cd $(ENV_DEV) && tofu plan

dev-apply:
	cd $(ENV_DEV) && tofu apply

# Publish website/ now (aws s3 sync + CloudFront invalidation) without a full apply.
dev-sync:
	cd $(ENV_DEV) && sh -ec "$$(tofu output -raw website_sync_command)"

dev-destroy:
	cd $(ENV_DEV) && tofu destroy

prod-init:
	cd $(ENV_PROD) && tofu init -backend-config=backend.hcl

prod-init-first:
	cd $(ENV_PROD) && cp -n backend.hcl.example backend.hcl && tofu init -backend-config=backend.hcl

# Phase A: create the ACM certificate, then add the DNS validation CNAMEs it prints.
prod-acm-cert:
	cd $(ENV_PROD) && tofu apply -target=module.acm.aws_acm_certificate.this && tofu output acm_dns_validation_records

# Phase B: after setting acm_wait_for_validation = true and the CNAMEs have propagated.
prod-acm-validate:
	cd $(ENV_PROD) && tofu apply -target=module.acm

prod-plan:
	cd $(ENV_PROD) && tofu plan

prod-apply:
	cd $(ENV_PROD) && tofu apply

# Publish website/ now (aws s3 sync + CloudFront invalidation) without a full apply.
prod-sync:
	cd $(ENV_PROD) && sh -ec "$$(tofu output -raw website_sync_command)"

fmt:
	tofu fmt -recursive .

validate: dev-init prod-init
	cd $(ENV_DEV) && tofu validate
	cd $(ENV_PROD) && tofu validate
