# Kubernetes Cluster Automation (Terraform + Ansible)

This repository provisions and bootstraps a multi-node Kubernetes cluster on AWS using Terraform for infrastructure and Ansible for configuration. It is intended as a reference implementation and portfolio project: readable, reproducible, and explicit about the moving parts (networking, certificates, systemd units, kubeconfigs), rather than a turnkey production blueprint.

## What this demonstrates

- Terraform module composition for networking, compute, and Kubernetes primitives
- Clear separation of concerns: infrastructure provisioning vs. node configuration
- Explicit certificate and kubeconfig generation for Kubernetes components
- Environment-scoped Terraform working directories (isolated init artifacts, locks, logs)
- A thin management layer to drive multi-environment workflows consistently

## Repository layout

- terraform/  
  Shared Terraform roots and modules.
  - terraform/infrastructure/ – shared infrastructure root (VPC, instances, etc.)
  - terraform/services/ – shared services root (cluster services and supporting components)
  - terraform/modules/ – reusable modules

- ansible/  
  Playbooks used to configure control plane and worker nodes after provisioning.

- management/  
  Operator-facing entry point for selecting environments and running Terraform.

- docker/, kubectl/
  Supporting scripts, images, manifests, and deployment tooling.

## High-level workflow

This project can be run, but it assumes you will review the code and provide your own AWS account, credentials, and environment configuration.

At a high level:

1. Define an environment via a .tfvars file in management/
2. Create a local AWS credentials file referenced by that .tfvars (not committed)
3. Use management/manage.sh to validate, plan, and apply infrastructure and services
4. Use helper commands (SSH menu, kubectl shell) to interact with the cluster

The management tooling is the intended entry point.

## Management directory

The management/ directory defines environments and drives Terraform in a consistent, repeatable way.

### Key files

- manage.sh  
  Interactive Terraform environment manager. It:
  - Discovers environments by locating management/<env>.tfvars
  - Creates and uses runtime directories under environments/<env>/
  - Runs Terraform from environment-specific working directories so each environment has its own:
    - .terraform data directory
    - .terraform.lock.hcl
    - generated artifacts
    - logs

- <env>.tfvars (example: dev.tfvars)  
  Primary environment definition file. This file is selected in the menu and passed as -var-file to both the infra and services Terraform roots.

- Optional overrides:
  - management/<env>.infra.tfvars – applied only to the infrastructure root
  - management/<env>.services.tfvars – applied only to the services root

- aws_creds.ini-template  
  Template for a local AWS credentials file. Environment .tfvars files may reference an aws_credentials_file path. The referenced file should be created locally and must not contain real credentials committed to git.

- sample.tfvars  
  Example environment definition to copy when creating a new environment.

### Environment runtime layout

For each environment, manage.sh creates the following structure at the repo root (ingored by git):

environments/
  <env>/
    infra/
      root/                # env-specific working dir (symlinks to shared terraform/infrastructure)
      .terraform/          # env-specific Terraform data dir (TF_DATA_DIR)
    services/
      root/                # env-specific working dir (symlinks to shared terraform/services)
      .terraform/          # env-specific Terraform data dir (TF_DATA_DIR)
    logs/                  # terraform plan/apply/destroy logs

Terraform is intentionally run from these environment-specific root/ directories rather than directly from terraform/infrastructure or terraform/services. This isolates environments from one another and keeps init artifacts, lock files, and generated outputs separate.

The root/ directories are kept in sync by symlinking files from the shared Terraform sources.

### Using manage.sh

From the repository root:

chmod +x management/manage.sh
./management/manage.sh

You will be prompted to select an environment based on the .tfvars files present in management/. The interactive menu provides:

- Configuration validation
- Terraform init (if needed)
- Plan/apply for infra and services
- Plan/apply each root independently
- Log inspection
- Controlled destroy (services first, then infra)
- Helper actions (SSH menu, kubectl shell)

### Defining a new environment

1. Copy the sample tfvars file:

cp management/sample.tfvars management/dev.tfvars

2. Create a local AWS credentials file:

cp management/aws_creds.ini-template management/aws_dev.ini
# edit management/aws_dev.ini with your local credentials

3. Reference that credentials file from your environment tfvars:

cloud_type           = "aws"
backend_type         = "s3"
aws_credentials_file = "${path.module}/aws_dev.ini"

The ${path.module} placeholder resolves to the management/ directory.

## Security notes

- No real credentials are committed to this repository.
- Credential files referenced by environment .tfvars are intended to be local-only.
- Terraform state, .terraform/, and generated artifacts should remain ignored by git.
- Repository history has been scanned for secrets.

## Status

This repository is evolving. The intent is to keep the structure stable and the workflow understandable, even as implementation details change.
