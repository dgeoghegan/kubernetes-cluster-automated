# artifact-schema.md

Terraform-derived artifact contract for Kubernetes Cluster Automation.

Defines inputs, derivation model, and output contract for cluster configuration generation.

---

## Artifact schema

All cluster configuration is computed during a single Terraform apply and written to S3 before any node executes configuration management or Kubernetes bootstrap steps.

Terraform is the authoritative renderer for all configuration artifacts. Downstream systems consume fully rendered files only and do not perform templating or configuration synthesis.

---

## Inputs

| Variable | Type | Effect |
| --- | --- | --- |
| `controller_max` | int | Drives controller count, etcd quorum size, and controller certificate SAN generation |
| `worker_max` | int | Drives worker count and pod CIDR allocation |
| `ha_enabled` | bool | Enforces minimum HA topology requirements: requires ≥3 AZs for the chosen instance type and an odd `controller_max` ≥ 3; Terraform rejects violating plans before any resources are created |
| `pod_cidr` | CIDR | Base range subdivided into per-worker pod CIDRs |
| `cluster_index` | int | Determines cluster VPC CIDR allocation (`cluster 0 → 10.0.0.0/16`, `cluster 1 → 10.1.0.0/16`) |
| `service_cidr` | CIDR | First host address reserved as Kubernetes API service IP and certificate SAN |

Availability zones are resolved at plan time from `data.aws_availability_zones.available`. The subnet count is derived from the greater of controller and worker counts, bounded by available AZs.

EC2 instance attributes including private IPs, public IPs, and DNS names become available within the Terraform dependency graph after instance creation. These values are referenced directly by downstream certificate and configuration resources during the same apply.

---

## Derivation model

All derivation occurs inside a single Terraform dependency graph. There is no separate render phase.

```text
Input variables
    ↓
VPC and subnet derivation
    ↓
EC2 instance creation
    ↓
Live instance attributes become available
    ↓
Certificate generation (SANs derived from instance attributes)
    ↓
Configuration rendering
    ↓
S3 object materialization
    ↓
Docker host sync (`aws s3 sync` into `/ansible/`)
````

Subnet allocation uses a deterministic logical CIDR derivation model for internal cluster planning. The number of subnet bits added scales with AZ fan-out:

* 1 AZ → 1 subnet bit
* 2-3 AZs → 2 subnet bits
* 4-7 AZs → 3 subnet bits

Controllers receive static private IPs at `.100 + index`; workers receive `.200 + index`. Nodes are distributed round-robin across derived subnets.

Per-worker pod CIDRs are allocated by adding 6 bits to `pod_cidr`, producing `/24` ranges:

* worker-0 → first `/24`
* worker-1 → second `/24`
* etc.

A `/18` pod CIDR supports up to 64 worker allocations.

Instance ordering for etcd cluster construction is derived from stable Terraform indices rather than AWS enumeration order.

---

## Output contract

Artifacts are stored as individual S3 objects. There is no manifest or secondary render step.

Three path prefixes are used:

```text
common/<filename>                 # cluster-wide shared artifacts
configs/controller/<node-name>/  # controller-specific artifacts
configs/worker/<node-name>/      # worker-specific artifacts
ansible/inventory.ini            # generated Ansible inventory
```

All artifacts are generated during a single Terraform apply. Nodes and Ansible are read-only consumers. They pull from S3 but never write back. Terraform is the only writer. Objects are overwritten when content changes on re-apply; the bucket has no versioning.

---

## Common artifacts

| File                                                              | Format       | Contents                                                                                                                                                                                                                                                           |
| ----------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ca.pem` / `ca-key.pem`                                           | PEM          | Cluster CA certificate and private key                                                                                                                                                                                                                             |
| `admin.pem` / `admin-key.pem`                                     | PEM          | Admin client certificate and key                                                                                                                                                                                                                                   |
| `kubernetes.pem` / `kubernetes-key.pem`                           | PEM          | Kubernetes API server certificate and key                                                                                                                                                                                                                          |
| `kube-proxy.pem` / `kube-proxy-key.pem`                           | PEM          | kube-proxy client certificate and key                                                                                                                                                                                                                              |
| `kube-controller-manager.pem` / `kube-controller-manager-key.pem` | PEM          | Controller-manager certificate and key                                                                                                                                                                                                                             |
| `kube-scheduler.pem` / `kube-scheduler-key.pem`                   | PEM          | Scheduler certificate and key                                                                                                                                                                                                                                      |
| `service-account.pem` / `service-account-key.pem`                 | PEM          | Service account signing key pair                                                                                                                                                                                                                                   |
| `kubernetes_ssh_key`                                              | PEM          | Cluster SSH private key                                                                                                                                                                                                                                            |
| `encryption-config.yaml`                                          | YAML         | Kubernetes EncryptionConfig using AES-CBC. Inherited from the tutorial source. AES-GCM is the current Kubernetes recommendation because it provides authenticated encryption and better performance on modern hardware. It would be the correct production choice. |
| `kube_scheduler_service`                                          | systemd unit | kube-scheduler.service                                                                                                                                                                                                                                             |
| `kube_scheduler_yaml`                                             | YAML         | KubeSchedulerConfiguration                                                                                                                                                                                                                                         |
| `kube_scheduler_kubeconfig`                                       | YAML         | Scheduler kubeconfig                                                                                                                                                                                                                                               |
| `kube_controller_manager_service`                                 | systemd unit | kube-controller-manager.service                                                                                                                                                                                                                                    |
| `kube_proxy_kubeconfig`                                           | YAML         | kube-proxy kubeconfig                                                                                                                                                                                                                                              |
| `admin_kubeconfig`                                                | YAML         | Administrative kubeconfig                                                                                                                                                                                                                                          |
| `kube-proxy-config.yaml`                                          | YAML         | KubeProxyConfiguration                                                                                                                                                                                                                                             |
| `workers.host`                                                    | plain text   | `/etc/hosts` entries for worker nodes                                                                                                                                                                                                                              |

---

## Per-controller artifacts

One artifact set is generated per controller node.

| File                                 | Format       | Contents                                                                  |
| ------------------------------------ | ------------ | ------------------------------------------------------------------------- |
| `etcd_service`                       | systemd unit | etcd.service with fully rendered `--initial-cluster` peer graph           |
| `kube_apiserver_service`             | systemd unit | kube-apiserver.service with rendered advertise address and etcd endpoints |
| `kube_controller_manager_kubeconfig` | YAML         | Controller-manager kubeconfig                                             |

---

## Per-worker artifacts

One artifact set is generated per worker node.

| File                   | Format       | Contents                                            |
| ---------------------- | ------------ | --------------------------------------------------- |
| `cert.pem` / `key.pem` | PEM          | Kubelet node certificate and key                    |
| `kubeconfig`           | YAML         | Worker kubeconfig                                   |
| `10-bridge.conf`       | JSON         | CNI bridge configuration with per-worker pod subnet |
| `kubelet-config.yaml`  | YAML         | KubeletConfiguration with assigned podCIDR          |
| `kubelet.service`      | systemd unit | kubelet.service with rendered hostname override     |

---

## Key invariants

### etcd peer graph is fully rendered before bootstrap

The `--initial-cluster` flag value is constructed during Terraform apply by iterating live controller instance attributes. The resulting value is stored as a final rendered string inside the generated systemd unit prior to S3 upload.

No controller performs peer discovery or cluster graph synthesis during bootstrap.

---

### No node generates configuration

Nodes do not perform templating, interpolation, or configuration synthesis.

Ansible selects the correct artifact directory using `{{ inventory_hostname }}` and copies pre-rendered files to destination paths without modification.

Terraform is the sole configuration renderer.

One exception exists: `kube-proxy.service` is defined inline within the Ansible playbook rather than copied from S3. The unit contains no node-specific values and does not materially affect the artifact-first invariant.

---

### Kubelet certificate identity is required by the Node Authorizer

Kubelet certificates use `CN=system:node:<worker-name>` and `O=system:nodes`. This format is required by the Kubernetes Node Authorizer, which grants each node access only to the secrets and configmaps bound to pods scheduled on that node. A kubelet presenting a certificate with the wrong CN format will register but have its API requests rejected.

The correct format is not arbitrary. It is the identity the Node authorization mode expects.

---

### Artifact generation is infrastructure-state dependent

Certificates, kubeconfigs, systemd units, and network configuration are derived directly from infrastructure state produced during the same Terraform apply.

This includes:

* EC2 private IPs
* DNS names
* subnet allocation
* pod CIDR assignment
* etcd peer topology

The artifact set is a rendered snapshot of the infrastructure state Terraform resolved during apply.

---

### CA private key is intentionally included in the artifact set

`ca-key.pem` is stored in S3 alongside the remaining cluster artifacts and synced to the Docker host during bootstrap.

This preserves deterministic cluster generation semantics and eliminates external PKI dependencies for the reference system.

This design is intended for deterministic cluster generation and reproducible bootstrap behavior, not production-grade secret isolation.

---

## Known limitations

### Single CA for all certificate types

A single CA signs all cluster certificates: etcd peer and client, API server, kubelet, kube-proxy, kube-scheduler, kube-controller-manager, and service accounts.

This is deliberate lab scoping. Production Kubernetes recommends at minimum a separate etcd CA to isolate blast radius and allow independent rotation schedules. In this architecture a single CA is acceptable because the cluster is short-lived and not intended for multi-operator use.

---

### Certificate and encryption key lifecycle

All certificates use a one-year validity period. The CA uses the same validity period as the leaf certificates it signs, which means the entire PKI expires simultaneously.

Standard practice sets CA validity significantly longer than leaf cert validity to allow leaf cert rotation within the CA lifetime. That rotation window does not exist here.

Certificate expiry and rotation are outside the scope of this architecture. A cluster approaching expiry requires a full rebuild.

Encryption key rotation follows the same pattern. No rotation path exists in this architecture, and it is out of scope for the same reason.