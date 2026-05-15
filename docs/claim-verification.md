# claim-verification.md

# Verification Walkthrough

This document maps architectural claims to concrete, inspectable behavior in the repository.

Each section defines:

* a system-level invariant
* how to falsify it
* what evidence must exist if it is true

It is not documentation of intent. It is a structural verification layer over the system.

---

## 1. Single orchestration entrypoint

### Claim

All cluster lifecycle operations are executed through a single orchestration script. No manual or secondary execution paths are used for provisioning, configuration distribution, or teardown.

### Verification

```bash
grep -RniE 'terraform apply|ansible-playbook|aws s3 sync' .

```

Expected:

* All lifecycle commands originate only from the orchestration script
* No ad-hoc execution paths exist outside it

Inspect repository entrypoints:

```bash
find . -maxdepth 2 -type f -name "*.sh"

```

Expected:

* One primary management script is responsible for lifecycle control

---

## 2. No managed Kubernetes services

### Claim

The cluster is fully self-managed on EC2 and does not use EKS, GKE, or AKS.

### Verification

```bash
grep -RniE '\beks\b|\bgke\b|\bak\s?sk\b|eksctl|gcloud|az aks' .

```

Expected:

* No managed Kubernetes provisioning tools present

```bash
grep -RniE 'aws_eks_cluster|aws_eks_node_group' terraform/

```

Expected:

* No EKS Terraform resources

---

## 3. No runtime configuration generation on nodes

### Claim

Nodes do not generate configuration. All configuration is pre-rendered before bootstrap.

### Verification

```bash
grep -RniE 'envsubst|template|render|sed |awk |cat >|echo .*>' .

```

Expected:

* No runtime synthesis of Kubernetes configuration

```bash
grep -RniE 'template:|lookup|set_fact|vars_prompt' ansible/

```

Expected:

* Ansible does not derive configuration values

Known exception: `kubectl_run.tf` uses `envsubst` to substitute `$CLUSTER_DNS` into the CoreDNS manifest at runtime inside the kubectl container before `kubectl apply`. CoreDNS is the cluster DNS resolver — this is not a peripheral component. The value (`cidrhost(var.service_cidr, 10)`) is Terraform-derived and deterministic, but the rendering occurs at runtime, not pre-execution.

---

## 4. Terraform is the sole derivation layer

### Claim

All configuration artifacts are generated during Terraform evaluation.

### Verification

```bash
grep -RniE 'helm|kustomize|kubectl apply|client-go|go-template' .

```

Expected:

* No external configuration synthesis tools used

---

## 5. S3 is a complete pre-execution snapshot

### Claim

S3 contains the full set of configuration artifacts required to bootstrap the cluster.

### Verification

```bash
grep -RniE 'aws_s3_object|put_object|s3://' terraform/

```

Expected:

* All artifacts are written during Terraform apply before execution begins

Check that Ansible does not write artifacts:

```bash
grep -RniE 's3|put|upload' ansible/

```

Expected:

* Ansible only reads from S3

---

## 6. Deterministic cluster topology derivation

### Claim

Cluster topology is derived from inputs and AWS state, not manually defined.

### Verification

```bash
grep -RniE 'i-0[a-f0-9]{8,}' terraform/

```

Expected:

* No static instance IDs

```bash
grep -n 'private_ip' terraform/modules/kubernetes/aws_instances.tf
```

Expected:

* All private IP assignments use `cidrhost()` — controllers at `.100 + index`, workers at `.200 + index`. No literal IP values.

Check HA constraint enforcement:

```bash
grep -n 'condition' terraform/modules/kubernetes/variables.tf terraform/modules/network/aws_vpc.tf
```

Expected:

* Validation block enforcing odd `controller_max ≥ 3` when `ha_enabled = true`
* Precondition block enforcing `max_zones ≥ 3` when HA is enabled

---

## 7. etcd topology is fully precomputed

### Claim

etcd peer configuration is fully defined before bootstrap and not discovered at runtime.

### Verification

```bash
grep -RniE '--initial-cluster|discovery|existing' .

```

Expected:

* No runtime discovery mechanisms

Expected presence:

* Fully rendered static peer list in generated configuration

---

## 8. Cross-root dependency enforcement (infra to services)

### Claim

The services layer cannot be applied without completed infrastructure state.

### Verification

```bash
grep -RniE 'remote_state' terraform/

```

Expected:

* Services root depends on infrastructure outputs

Check ordering constraint:

* Infra apply must complete before services apply
* Missing infra state causes services plan failure

---

## System invariant

Across all checks, the system maintains a single property:

> Cluster state is fully defined during Terraform evaluation and remains independent of all node runtime behavior prior to bootstrap.

This invariant is enforced through structural constraints rather than runtime guarantees.
