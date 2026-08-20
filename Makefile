.PHONY: help sftp-up airbyte-up connectors-up seed sync status diagnose down

help:
	@echo "Targets: sftp-up airbyte-up connectors-up seed sync status diagnose down"
	@echo "Apply order: sftp-up -> airbyte-up -> seed -> connectors-up -> sync"

sftp-up:
	cd sftp/environments/dev/local-test && terraform init && terraform apply

airbyte-up:
	cd airbyte/terraform && terraform init && terraform apply

seed:
	./sftp/scripts/seed-sample-csv.sh

connectors-up:
	@echo "Export env first: eval \"\$$(./sftp/scripts/export-airbyte-env.sh)\""
	@echo "                 eval \"\$$(cd airbyte/terraform && terraform output -raw export_dest_postgres_env_command)\""
	cd connectors/environments/dev && terraform init && terraform apply

sync:
	cd connectors/environments/dev && $$(terraform output -raw trigger_sync_command)

status:
	cd airbyte && $$(cd terraform && terraform output -raw kubectl_command)

diagnose:
	cd airbyte && ./scripts/diagnose.sh

down:
	cd connectors/environments/dev && terraform destroy -auto-approve || true
	cd airbyte/terraform && terraform destroy -auto-approve || true
	cd sftp/environments/dev/local-test && terraform destroy -auto-approve || true
