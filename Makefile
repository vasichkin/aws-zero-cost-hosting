# Usage: make <target> [ARGS=-auto-approve]   (ARGS is passed to tofu apply / destroy)
ENVS := dev prod
# prod uses the S3 backend created by `make bootstrap` (see infra/environments/prod/backend.hcl.example)
INIT_prod := -backend-config=backend.hcl

.PHONY: help setup bootstrap $(ENVS:%=%-apply) $(ENVS:%=%-destroy) $(ENVS:%=%-sync)

help:
	@echo "setup                       wizard: ask project settings, write tfvars + backend.hcl from the *.example files"
	@echo "bootstrap                   create the remote state bucket (once per AWS account)"
	@echo "dev-apply   | prod-apply   init + apply an environment (includes website sync + CloudFront invalidation)"
	@echo "dev-destroy | prod-destroy destroy an environment (asks for confirmation; deletes the site bucket content)"
	@echo "dev-sync    | prod-sync    publish website/ now: aws s3 sync + CloudFront invalidation, no full apply"

setup:
	scripts/setup.sh

bootstrap:
	cd infra/bootstrap && tofu init -input=false && tofu apply $(ARGS)

$(ENVS:%=%-apply): %-apply:
	cd infra/environments/$* && tofu init -input=false $(INIT_$*) && tofu apply $(ARGS)

$(ENVS:%=%-destroy): %-destroy:
	cd infra/environments/$* && tofu init -input=false $(INIT_$*) && tofu destroy $(ARGS)

$(ENVS:%=%-sync): %-sync:
	cd infra/environments/$* && sh -ec "$$(tofu output -raw website_sync_command)"
