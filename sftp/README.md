# Local Juju SFTP model, managed with Terraform

> Part of the **airbyte-sftp-local-lab** monorepo. See [../README.md](../README.md).


Terraform plans that stand up a local Juju model running a key-authenticated, SFTP-only endpoint on an Ubuntu machine.

Terraform owns the whole lifecycle:

- creates the Juju model on a configurable cloud (LXD by default)
- deploys the `ubuntu` charm with a single unit
- generates a dedicated ed25519 keypair for the SFTP user
- registers your client SSH key with the model so `juju ssh` works
- creates the SFTP user, installs the public key, and locks `sshd` down to
  SFTP-only access for that user
- outputs a ready-to-run `sftp` command

## Layout

```
terraform/                    Terraform root module
  versions.tf                 provider + Terraform version pins
  providers.tf                Juju provider configuration
  variables.tf                all tunables
  main.tf                     model, application, keypair, in-unit config
  outputs.tf                  connection details
  terraform.tfvars.example    copy to terraform.tfvars to customise
scripts/
  apply-sftp.sh               waits for the unit, then applies the config
  remote-sftp-setup.sh        runs on the unit: user, keys, sshd Match block
```

## Prerequisites

- `terraform` >= 1.5
- `juju` 3.x CLI
- `jq`
- LXD initialised (`lxd init --auto`) if you use the default cloud
- A client SSH keypair (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`)
- **A bootstrapped Juju controller.** Terraform does not bootstrap one:

  ```bash
  juju bootstrap localhost lxd-controller
  ```

The Juju provider reads your local Juju CLI configuration from
`~/.local/share/juju` and targets the currently selected controller. To point at
a different controller, export `JUJU_CONTROLLER_ADDRESSES`, `JUJU_USERNAME`,
`JUJU_PASSWORD` and `JUJU_CA_CERT`.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional, all values have defaults
terraform init
terraform plan
terraform apply
```

Apply takes a few minutes on a cold LXD image cache, most of it spent waiting
for the machine to reach `active/idle`.

On success:

```
private_key_path  = "/home/you/.ssh/sftpuser"
sftp_command      = "sftp -i /home/you/.ssh/sftpuser sftpuser@10.60.7.141"
sftp_host         = "10.60.7.141"
sftp_landing_path = "/home/sftpuser/upload"
sftp_user         = "sftpuser"
```

## Verifying

Connect and upload a file:

```bash
eval "$(terraform output -raw sftp_command)"
```

```
sftp> pwd
Remote working directory: /home/sftpuser/upload
sftp> put ./somefile.txt
sftp> ls -l
```

Or seed the bundled sample CSV:

```bash
./scripts/seed-sample-csv.sh
```

Interactive shell access is refused by design:

```bash
ssh -i "$(terraform output -raw private_key_path)" \
    "$(terraform output -raw sftp_user)@$(terraform output -raw sftp_host)" id
# This service allows sftp connections only.
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `model_name` | `sftp` | Juju model name |
| `juju_cloud` | `localhost` | Cloud the model is created on |
| `juju_cloud_region` | `localhost` | Cloud region |
| `app_name` | `ubuntu` | Juju application name |
| `charm_channel` | `latest/stable` | Charmhub channel for the `ubuntu` charm |
| `charm_base` | `ubuntu@24.04` | Base the charm is deployed on |
| `machine_constraints` | `""` | Juju constraints, e.g. `mem=4G cores=2` |
| `sftp_user` | `sftpuser` | Unix user created on the unit |
| `sftp_dir` | `upload` | Landing directory under the user's home |
| `ssh_key_path` | `~/.ssh/sftpuser` | Where the generated RSA PEM private key is written |
| `juju_ssh_public_key_path` | auto-detected | Client key registered with the model |
| `wait_timeout` | `20m` | How long to wait for the unit to become ready |

Targeting a different machine cloud:

```hcl
# terraform.tfvars
juju_cloud          = "aws"
juju_cloud_region   = "eu-west-1"
machine_constraints = "mem=4G cores=2"
```

> The `ubuntu` charm is a machine charm, so `juju_cloud` must name a machine
> cloud. Kubernetes clouds (MicroK8s, `kind`, …) are not supported by this
> module.

## How the in-unit configuration is applied

The Juju Terraform provider can create models, applications and SSH keys, but it
cannot run commands inside a unit. So `terraform_data.sftp_config` shells out to
`scripts/apply-sftp.sh`, which:

1. waits for the unit to reach `active/idle` via `juju wait-for`
2. copies `scripts/remote-sftp-setup.sh` to the unit with `juju scp`
3. executes it with `juju ssh`, passing the public key base64-encoded

`juju ssh` only forwards stdin when it is a pipe, not when it is a regular file.
The original `bash -s < remote-sftp-setup.sh` therefore ran nothing at all and
still exited 0. Copying the script sidesteps the issue entirely. (A heredoc or
`cat script | juju ssh ...` also works, since both produce a pipe.)

The resource is replaced, and the configuration reapplied, whenever the
application, public key, `sftp_user`, `sftp_dir`, or the remote script itself
changes. Both scripts are idempotent, so reapplying is safe.

Terraform cannot see drift *inside* the unit. If someone edits `sshd_config` by
hand, force a reapply:

```bash
terraform apply -replace=terraform_data.sftp_config
```

## Troubleshooting

### `Enter a value:` after `terraform apply`

This is the approval prompt, not a missing variable — every variable in this
module has a default. Type `yes` (only the literal string is accepted; `y` or a
bare Enter cancels), or run `terraform apply -auto-approve`.

If the prompt is preceded by a variable name and description, you are being
asked for an input variable instead, which means you are running from a
different directory or `variables.tf` was modified.

### The model already exists

`model_name` defaults to `sftp`. If a model of that name already exists but is
not in Terraform state, apply will fail or fight with it. Either pick another
name:

```bash
terraform apply -var model_name=sftp-dev
```

destroy the existing one, if it was hand-built and disposable:

```bash
juju destroy-model sftp --no-prompt
```

or import it and let Terraform take over:

```bash
terraform import juju_model.sftp "$(juju show-model sftp --format=json | jq -r '.sftp["model-uuid"]')"
```

### `Permission denied (publickey)` during the provisioner

The client key was not registered with the model. Check that
`juju_ssh_key.client` exists in state and that `juju ssh-keys -m <model>` lists
your key. If you have no default key, generate one with `ssh-keygen -t ed25519`
or point `juju_ssh_public_key_path` at an existing public key.

### Uploads work but the config looks stale

Terraform cannot see changes made inside the unit. Force a reapply:

```bash
terraform apply -replace=terraform_data.sftp_config
```

## Teardown

```bash
terraform destroy
```

This destroys the model and its machine. The generated key files are removed
too, since they are managed as Terraform resources.

## Using with local Airbyte

Export connection details for `connectors (this monorepo)/environments/dev`:

```bash
eval "$(./scripts/export-airbyte-env.sh)"
```

That sets `TF_VAR_SFTP_HOST`, `TF_VAR_SFTP_USER`, `TF_VAR_SFTP_PRIVATE_KEY`, and
`TF_VAR_SFTP_FOLDER_PATH` (the absolute landing path such as
`/home/sftpuser/upload`). Airbyte pods must use the LXD unit IP and that
absolute folder path — there is no chroot, so `/` is the host root.

The private key is **RSA PEM** (not ed25519). Airbyte `source-sftp-bulk` fails
to list files with OpenSSH ed25519 keys (`unpack requires a buffer of 4 bytes`).

See also `airbyte/` (kind Airbyte + destination Postgres).

## Security notes

- The generated private key is written to disk **and stored in Terraform
  state**. Treat `terraform.tfstate` as a secret: it is git-ignored here, and
  should never be committed or shared.
- The SFTP user has a `nologin` shell and is restricted with `ForceCommand
  internal-sftp`, `AuthenticationMethods publickey`, and no TCP/agent/X11
  forwarding.
- There is no chroot: the user can read paths outside its landing directory that
  are world-readable. Add `ChrootDirectory` to `remote-sftp-setup.sh` if you
  need stricter isolation.
