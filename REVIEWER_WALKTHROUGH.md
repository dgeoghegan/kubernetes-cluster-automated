# Reviewer Walkthrough

## 1. Goals for this Demo

This project demonstrates the provisioning and operation of a Kubernetes control plane and worker nodes on AWS using only AWS primitives, without relying on managed Kubernetes services such as EKS.

## 2. Where the Kubernetes Cluster Lives

This cluster runs entirely inside a single AWS account, within a VPC spanning multiple availability zones. Kubernetes control-plane components run directly on EC2 instances provisioned by Terraform, alongside separate EC2 worker nodes. AWS provides only foundational primitives such as compute, networking, and IAM; Kubernetes itself, including control-plane services and node configuration, is owned and managed by the user rather than delegated to a managed service. All infrastructure lifecycle is expressed in Terraform, while ordered configuration, bootstrap, and recovery behavior is handled explicitly through Ansible and kubectl.

Relevant code locations:
- [`terraform/modules/kubernetes/aws_instances.tf`](terraform/modules/kubernetes/aws_instances.tf)
- [`terraform/modules/network/aws_vpc.tf`](terraform/modules/network/aws_vpc.tf)

## 3. Design Decisions and Inspection Paths

### Decision 1: Kubernetes runs directly on EC2 instances, not a managed service

Kubernetes control-plane and worker nodes are provisioned as EC2 instances and configured explicitly rather than through a managed service.

How to inspect:
- Inspect [`terraform/modules/kubernetes/aws_instances.tf`](terraform/modules/kubernetes/aws_instances.tf) for EC2 instance resources designated as control-plane and worker nodes.
- Inspect [`terraform/modules/network/aws_vpc.tf`](terraform/modules/network/aws_vpc.tf) for VPC, subnet, and routing resources used by the cluster nodes.
- Inspect [`ansible/playbooks/`](ansible/playbooks/) for playbooks that install and configure Kubernetes control-plane and worker components on EC2.

Absence:
- From the repository root, run `grep -ri eks .` and verify that it produces zero matches for any EKS resources.

### Decision 2: Cluster topology and addressing are derived dynamically

Cluster topology and addressing are determined dynamically based on minimal configurations (node count, AWS region) rather than being hard-coded.

How to inspect:
- Inspect [`terraform/modules/network/aws_vpc.tf`](terraform/modules/network/aws_vpc.tf) to see each subnet's AZ and CIDR determined based on the number of nodes and available AZs.
- Inspect [`terraform/modules/kubernetes/aws_instances.tf`](terraform/modules/kubernetes/aws_instances.tf) to see that each node’s name, subnet, and private IP are derived values.
- Inspect [`terraform/modules/kubernetes/config_contents.tf`](terraform/modules/kubernetes/config_contents.tf) to see that Ansible inventory contents are generated from derived values.

Absence:
- From the repository root, execute `grep -RniE '\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(/(3[0-2]|[12]?[0-9]))?\b' .` to confirm that only broad CIDR ranges appear (only to be dynamically subdivided) and no per-node static addressing is encoded.

### Decision 3: Infrastructure provisioning is separated from ordered configuration

The system separates infrastructure provisioning from asset configuration by using Terraform for lifecycle ownership and Ansible for procedural bootstrap and recovery.

How to inspect:
- Inspect [`terraform/infrastructure/main.tf`](terraform/infrastructure/main.tf) and [`terraform/modules`](terraform/modules) to see that Terraform resources are limited to infrastructure concerns.
- Inspect [`ansible/playbooks/`](ansible/playbooks/) to see how Ansible installs and configures all Kubernetes components.

Absence:
- Execute `grep -RniE 'remote-exec|local-exec|cloud-init|/usr/local|/usr/bin/|/etc/|apt|user_data|install |apt |apt-|file\s*\{' terraform/`and confirm that those commands or keywords appear only for establishing infrastructure (Docker host's user_data), generating environment-specific configuration files (Kubernetes-related certificates), or invoking a runner for Ansible or kubectl.

## 4. Lifecycle Evidence

### Bring-up

Commands:
```bash
git clone https://github.com/dgeoghegan/kubernetes-cluster-automated
cd kubernetes-cluster-automated

cp management/aws_creds.ini-template management/aws_creds.ini
# Edit management/aws_creds.ini and set:
# aws_access_key_id, aws_secret_access_key, region

chmod +x management/manage.sh

cd management
printf "4\n" | ./manage.sh
# Or execute ./manage.sh and choose option 4
```

Code paths involved:
- management/manage.sh
- management/*.tfvars
- terraform/infrastructure/
- terraform/services/
- terraform/modules/ansible_runner/
- terraform/modules/kubectl_runner/
- kubectl/manifests/
- environments/<env>/infra/root/
- environments/<env>/services/root/

Invariant:
The system enforces environment-scoped Terraform state and execution directories regardless of how many times bring-up is run or by whom.

### Teardown

```bash
cd "$(git rev-parse --show-toplevel)/management"
printf "10\nsample\n" | ./manage.sh
# Or execute ./manage.sh, choose option 10, and follow the prompts 
```

## 5. Supported Entrypoints and Constraints

Engineers install Terraform locally and do not install Ansible or kubectl. Terraform provisions a Docker host VM during bring-up, and Ansible and kubectl are executed inside containers on that host using images and entrypoints defined by the system.

The system does not depend on hidden workstation state such as user home directories, global kubeconfig files, or cached tool data. Terraform runs from explicit, environment-scoped directories under environments/, with Terraform state and initialization data isolated per environment. Ansible and kubectl configuration and outputs are generated and used inside system-managed directories and containers rather than on the engineer’s machine.

Note:
Interactions with the system are operated through [`management/manage.sh`](management/manage.sh), which serves as the single entrypoint for environment selection and lifecycle actions. All actions are then executed by Terraform or by a containerized runner for Ansible or kubectl. 

## 6. Explicit Non-Goals

This demo does not:
- Implement a multi-region Kubernetes cluster or cross-region failover.
- Include application workloads deployed onto the Kubernetes cluster.
- Integrate with external CI/CD pipelines or platform-level orchestration services.
- Provide a production-ready Kubernetes distribution or vendor-specific hardening.
- Implement automated Kubernetes or operating system upgrade paths.
- Address observability, alerting, or SRE-style operational monitoring.
- Model scale, cost optimization, or performance tuning beyond functional correctness.
- Cover day-2 operations beyond the explicit bring-up, change, and teardown paths demonstrated.
