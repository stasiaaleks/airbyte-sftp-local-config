# Terraform state after the monorepo move

State files were **copied** from the original directories into this monorepo so
you can keep managing live resources from here.

| Root | State path | Original (do not apply both) |
| --- | --- | --- |
| `sftp/` | `sftp/terraform/terraform.tfstate` | `comsys-sftp-terraform-plans/terraform/` |
| `airbyte/` | `airbyte/terraform/terraform.tfstate` | `airbyte-local-terraform-plans/terraform/` |
| `connectors/` | `connectors/environments/dev/terraform.tfstate` | `airbyte-connector-terraform-plans/environments/dev/` |

**Important:** after this copy, treat the monorepo as the only write path.
Applying from both the old and new locations can corrupt state or fight over
the same resources.

Original repos keep README redirects and leftover state backups for destroy
only if something went wrong.
