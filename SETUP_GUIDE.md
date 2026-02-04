# SETUP_GUIDE.md

## 1. What this provisions

A multi–availability zone AWS VPC and EC2 instances that form a highly available Kubernetes control plane plus worker nodes, provisioned via Terraform and configured and bootstrapped via Ansible, with a dedicated “docker-server” host used as the containerized operational tooling execution context (Ansible runner and kubectl runner).

## 2. Preconditions

AWS account and credentials: You must provide an AWS access key and secret key with permissions to create and destroy VPC networking, EC2 instances, IAM resources, security groups, load balancers, and S3. Credentials are provided via a shared-credentials INI file referenced by the environment tfvars.

Local tools:
- Bash shell
- git
- terraform (the script enforces terraform >= 1.5.0)
- ssh client

Cost and time bounds: Not stated in-repo. Expect AWS charges while the environment exists (EC2, load balancer, S3, etc.). Destroy when finished.

Required local files to create before execution:
- `management/aws_creds.ini` (copy from `management/aws_creds.ini-template` and populate `aws_access_key_id`, `aws_secret_access_key`, and `region`)
- `management/sample.tfvars` is the single environment definition used by `manage.sh`

## 3. Repository layout map

- `management/`
  - `manage.sh` (single operator entrypoint)
  - `sample.tfvars` (authoritative environment definition)
  - `aws_creds.ini-template`
- `terraform/`
  - `infrastructure/` (Terraform root 1: AWS primitives and EC2 nodes)
  - `services/` (Terraform root 2: Ansible runner and kubectl runner image)
  - `modules/` (shared Terraform modules)
- `ansible/`
  - `playbooks/` (invoked from the services root)
  - roles, templates, and inventory logic
- `environments/` (created at runtime)
  - `<env>/infra/root/`
  - `<env>/services/root/`
  - `<env>/logs/`

## 4. Single execution path

```bash
git clone https://github.com/dgeoghegan/kubernetes-cluster-automated
cd kubernetes-cluster-automated

cp management/aws_creds.ini-template management/aws_creds.ini
# Edit management/aws_creds.ini and set:
# aws_access_key_id, aws_secret_access_key, region

chmod +x management/manage.sh

cd management
printf "4\n" | ./manage.sh
````

Intentional change (scale workers from 3 to 2 and re-apply):

```bash
cd "$(git rev-parse --show-toplevel)"
perl -pi -e 's/^(worker_max\s*=\s*)3\s*$/\12/' management/sample.tfvars

cd management
printf "4\n" | ./manage.sh
```

## 5. Verification

```bash
cd "$(git rev-parse --show-toplevel)"

ENV_NAME="sample"

INFRA_WD="environments/${ENV_NAME}/infra/root"
INFRA_DATA="environments/${ENV_NAME}/infra/.terraform"

SERV_WD="environments/${ENV_NAME}/services/root"
SERV_DATA="environments/${ENV_NAME}/services/.terraform"

DOCKER_IP="$(TF_DATA_DIR="$INFRA_DATA" terraform -chdir="$INFRA_WD" output -raw docker_server_public_ip)"
SSH_KEY="${INFRA_WD}/files_from_terraform/docker_ssh_key"

REGISTRY_ADDR="$(TF_DATA_DIR="$SERV_DATA" terraform -chdir="$SERV_WD" output -raw registry_address)"
REGISTRY_USER="$(TF_DATA_DIR="$SERV_DATA" terraform -chdir="$SERV_WD" output -raw registry_user)"
REGISTRY_PASS="$(TF_DATA_DIR="$SERV_DATA" terraform -chdir="$SERV_WD" output -raw registry_pass)"
KUBECTL_IMAGE="$(TF_DATA_DIR="$SERV_DATA" terraform -chdir="$SERV_WD" output -raw kubectl_image_remote)"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$DOCKER_IP" \
  "docker login $REGISTRY_ADDR -u $REGISTRY_USER -p '$REGISTRY_PASS' >/dev/null && \
   docker run --rm \
     -v /ansible:/ansible \
     -e KUBECONFIG=/ansible/common/admin_kubeconfig \
     $KUBECTL_IMAGE get nodes -o wide"
```

Expected signals:

* Command exits successfully.
* Output shows Kubernetes nodes in `Ready` status.
* After the intentional change, the worker node count reflects the updated value.

## 6. Teardown

```bash
cd "$(git rev-parse --show-toplevel)/management"
printf "10\nsample\n" | ./manage.sh
```

## 7. Known sharp edges

* Readiness timing: first-time provisioning frequently encounters readiness races (SSH not yet available, cloud-init still running, Kubernetes components not yet ready). Failures typically occur during the services phase even when infrastructure provisioning has completed. The mitigation is to wait and re-run the same `Apply both` path; the system is designed to be safely re-runnable and converge.
