.PHONY: bootstrap-init bootstrap-plan bootstrap-apply dev-init dev-plan dev-apply dev-destroy prod-init prod-plan prod-apply fmt validate

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

dev-destroy:
	cd $(ENV_DEV) && tofu destroy

prod-init:
	cd $(ENV_PROD) && tofu init -backend-config=backend.hcl

prod-init-first:
	cd $(ENV_PROD) && cp -n backend.hcl.example backend.hcl && tofu init -backend-config=backend.hcl

prod-plan:
	cd $(ENV_PROD) && tofu plan

prod-apply:
	cd $(ENV_PROD) && tofu apply

fmt:
	tofu fmt -recursive .

validate: dev-init prod-init
	cd $(ENV_DEV) && tofu validate
	cd $(ENV_PROD) && tofu validate
