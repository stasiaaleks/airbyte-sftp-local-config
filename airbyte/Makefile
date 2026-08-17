TERRAFORM := /snap/bin/terraform

$(TERRAFORM):
	(snap list | grep -q terraform) || sudo snap install terraform --classic

.PHONY: fmt
fmt: # Format Terraform files using the default rules.
	terraform fmt -recursive

.PHONY: lint
lint: # Run all linters.
	terraform fmt -recursive -check
	cd terraform && terraform init -backend=false
	cd terraform && terraform validate

.PHONY: up
up: # Create the kind cluster and install Airbyte.
	cd terraform && terraform init && terraform apply

.PHONY: down
down: # Destroy the cluster and everything on it.
	cd terraform && terraform destroy

.PHONY: diagnose
diagnose: # Report cluster, pod, data and access state of the instance.
	./scripts/diagnose.sh

.PHONY: status
status: # Show Airbyte pods.
	cd terraform && $$(terraform output -raw kubectl_command)

.PHONY: health
health: # Check the public API is answering.
	cd terraform && $$(terraform output -raw health_check_command)
