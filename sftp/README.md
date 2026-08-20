# Local Juju SFTP model, managed with Terraform

> Part of the **airbyte-sftp-local-lab** monorepo. See [../README.md](../README.md).

Terraform plans that stand up a local Juju model running a **chrooted**,
key-authenticated SFTP-only endpoint on an Ubuntu 24.04 machine.

Terraform owns the whole lifecycle:

- creates the Juju model on a configurable cloud (LXD by default)
- deploys a bare `juju_machine` on the chosen Ubuntu base
- generates a dedicated RSA keypair for the SFTP user
- registers your client SSH key with the model so `juju ssh` works
- calls `modules/sftp-server` to configure the SFTP user, chroot, writable
  directories and an sshd drop-in via `juju ssh`
- outputs a ready-to-run `sftp` command

## Layout

```
modules/
  sftp-server/                  Reusable module (same shape as the prod
                                repo): juju_machine + null_resource driving
                                configure/cleanup scripts over `juju ssh`.
    scripts/
      configure-sftp-server.sh          local wrapper
      configure-sftp-server-remote.sh   runs on the machine
      cleanup-sftp-user.sh              local wrapper (destroy-time)
      cleanup-sftp-user-remote.sh       runs on the machine

environments/
  dev/local-test/               Locally deployable root that owns the model,
                                the RSA keypair, and the client SSH key.
    versions.tf providers.tf variables.tf main.tf outputs.tf
    terraform.tfvars.example

scripts/
  machine-address.sh            resolves the machine IP for outputs
  seed-sample-csv.sh            uploads samples/sample.csv into /uploads
  export-airbyte-env.sh         emits TF_VAR_SFTP_* exports for connectors/

samples/sample.csv              tiny CSV for smoke tests
```

Add a new "integration" by copying `environments/dev/local-test/` to
`environments/dev/<name>/`, tweaking `machine_name`, `sftp_user`,
`sftp_root`, `directories`, and (if you want isolation) `juju_model_name`.

## Prerequisites

- `terraform` >= 1.7.2
- `juju` 3.x CLI
- `jq`
- LXD initialised (`lxd init --auto`) if you use the default cloud
- A client SSH keypair (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`)
- **A bootstrapped Juju controller.** Terraform does not bootstrap one:

  ```bash
  juju bootstrap localhost lxd-controller
  ```

The Juju provider reads your local Juju CLI configuration from
`~/.local/share/juju` and targets the currently selected controller. To point
at a different controller, export `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, `JUJU_PASSWORD` and `JUJU_CA_CERT`.

## Usage

```bash
cd environments/dev/local-test
cp terraform.tfvars.example terraform.tfvars   # optional, all values have defaults
terraform init
terraform plan
terraform apply
```

Apply takes a few minutes on a cold LXD image cache, most of it spent waiting
for the machine to reach an `active/idle`-equivalent hostname.

On success:

```
private_key_path  = "/home/you/.ssh/sftp-local-test"
sftp_chroot_path  = "/srv/sftp/sftpuser"
sftp_command      = "sftp -i /home/you/.ssh/sftp-local-test sftpuser@10.60.7.141"
sftp_host         = "10.60.7.141"
sftp_landing_path = "/uploads"
sftp_user         = "sftpuser"
```

## Verifying

Connect and drop a file into `/uploads` (the first writable directory):

```bash
eval "$(terraform output -raw sftp_command)"
```

```
sftp> cd /uploads
sftp> pwd
Remote working directory: /uploads
sftp> put ../../samples/sample.csv
sftp> ls -l
```

Or seed the bundled sample CSV:

```bash
./scripts/seed-sample-csv.sh
```

Interactive shell access is refused by design:

```bash
ssh -i "$(terraform output -raw private_key_path)" \
    "$(terraform output -raw sftp_user)@$(terraform output -raw sftp_host)"
# This service allows sftp connections only.
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `juju_model_name` | `local-sftp` | Juju model name |
| `juju_cloud` | `localhost` | Cloud the model is created on |
| `juju_cloud_region` | `localhost` | Cloud region |
| `machine_name` | `local-test-sftp` | Juju machine name |
| `ubuntu_base` | `ubuntu@24.04` | Base of the Ubuntu machine |
| `sftp_user` | `sftpuser` | Unix user created inside the chroot |
| `sftp_group` | `sftpusers` | Unix group |
| `sftp_root` | `/srv/sftp` | Root that hosts each account's chroot (`<sftp_root>/<sftp_user>`) |
| `directories` | `["uploads", "processed"]` | Writable directories created inside the chroot |
| `sftp_private_key_path` | `~/.ssh/sftp-local-test` | Where the generated RSA PEM private key is written |
| `juju_ssh_public_key_path` | auto-detected | Client key registered with the model |

Targeting a different machine cloud:

```hcl
# terraform.tfvars
juju_cloud        = "aws"
juju_cloud_region = "eu-west-1"
```

> The machine is a plain `juju_machine`, so `juju_cloud` must name a machine
> cloud. Kubernetes clouds (MicroK8s, `kind`, …) are not supported.

## How the in-machine configuration is applied

The module (`modules/sftp-server`) creates a `juju_machine` and a
`null_resource` that shells out to `scripts/configure-sftp-server.sh`, which
pipes `scripts/configure-sftp-server-remote.sh` into `sudo bash` on the target
machine via `juju ssh`. The remote script:

1. installs `openssh-server` if missing
2. creates `sftp_group` and the `sftp_user` (chroot-owned `nologin` account)
3. builds `<sftp_root>/<sftp_user>`, then the requested writable
   `directories` inside it
4. installs the module's `ssh_public_keys` into
   `~sftp_user/.ssh/authorized_keys`
5. writes `/etc/ssh/sshd_config.d/90-sftp-<user>.conf` with `ChrootDirectory`,
   `ForceCommand internal-sftp`, publickey-only auth, no forwarding
6. `sshd -t`-validates and restarts ssh **only** when config changed

Any change to `sftp_user`, `sftp_group`, `sftp_root`, `directories`,
`ssh_public_keys`, or the scripts themselves re-runs the configure step. On
resource replacement (e.g. an `sftp_user` rename) the destroy-time provisioner
runs `cleanup-sftp-user.sh` first, revoking the old account and its sshd
drop-in **without deleting SFTP data**.

Terraform cannot see drift *inside* the machine. If someone edits
`sshd_config` by hand, force a reapply:

```bash
terraform apply -replace=module.sftp.null_resource.configure_sftp
```

## Teardown

```bash
terraform destroy
```

This destroys the model and its machine. The generated key files are removed
too, since they are managed as Terraform resources.

## Using with local Airbyte

Export connection details for `connectors/environments/dev` (in the sibling
`connectors/` root):

```bash
eval "$(./scripts/export-airbyte-env.sh)"
```

That sets `TF_VAR_SFTP_HOST`, `TF_VAR_SFTP_USER`, `TF_VAR_SFTP_PORT`,
`TF_VAR_SFTP_FOLDER_PATH` (chroot-relative, e.g. `/uploads`), and
`TF_VAR_sftp_private_key_path`.

The private key is **RSA PEM** (not ed25519). Airbyte `source-sftp-bulk` fails
to list files with OpenSSH ed25519 keys (`unpack requires a buffer of 4
bytes`).

See also `../airbyte/` (kind Airbyte + destination Postgres).

## Security notes

- The generated private key is written to disk **and stored in Terraform
  state**. Treat `terraform.tfstate` as a secret: it is git-ignored here, and
  should never be committed or shared.
- The SFTP user has a `nologin` shell and is restricted with
  `ChrootDirectory`, `ForceCommand internal-sftp`, `PasswordAuthentication no`,
  `PubkeyAuthentication yes`, and no TCP/agent/X11 forwarding.
- Because the account is chrooted, paths outside `<sftp_root>/<sftp_user>` are
  not visible to it at all.
