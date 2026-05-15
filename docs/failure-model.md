# failure-model.md

Failure model for Kubernetes Cluster Automation.

Classifies failure modes by where in the lifecycle they are detectable.

---

## Failure Model

Failure modes are grouped into four categories:

* runtime failure modes (protocol and distributed system behavior)
* artifact correctness failures (semantic validity of derived configuration)
* infrastructure tooling constraints (external system limitations)
* implementation complexity (design decisions that added development cost without proportional value)

---

## Runtime Failure Modes

### Protocol-Level Failures

#### Synchronous Bootstrap Without Reconciliation

Bootstrap phases execute sequentially without intermediate verification of distributed system state.

etcd is installed and started on controller nodes, after which execution proceeds without confirming quorum formation.

No reconciliation mechanism exists between bootstrap phases.

**Consequence:**
etcd failure is only observable when downstream components such as the API server attempt to connect to the datastore. Partial failure and successful initialization are indistinguishable until that point.

---

#### etcd Quorum Formation

etcd cluster formation uses `--initial-cluster-state new`, which is a single-use initialization mode.

The peer graph is fully rendered during Terraform evaluation and embedded in system configuration artifacts.

**Failure condition:**
If node identity, networking configuration, or startup state deviates after initial formation, etcd rejects its data directory and cannot rejoin the cluster.

**Re-apply risk:**
The etcd service unit restart is gated on file content changes. A re-apply that does not alter controller topology, IPs, or `cluster_index` copies an identical service unit, registers no change, and does not restart etcd. A re-apply that does change those inputs restarts etcd with `--initial-cluster-state new` against an already initialized data directory, which corrupts the cluster and requires full reinitialization.

**Property:**
Cluster formation is non-recoverable without manual reset of all members.

---

### Ordering-Readiness Gap

Terraform's dependency graph expresses resource ordering but not operational readiness. This is a structural property of the tooling.

An EC2 instance marked "created" by Terraform may not yet be reachable via SSH, may not have completed cloud-init, and may not have any installed services available. Downstream resources that depend on instance creation may attempt to connect to a host that cannot accept connections yet.

Similarly, Ansible completing a playbook run does not mean the Kubernetes API server is ready to serve requests.

**Consequence:**
Applying manifests before the API server is ready produces indeterminate cluster state. Resources may be partially applied against an unready control plane with no clear error.

**Current compensations:**
A 60-iteration curl loop against the API server health endpoint gates manifest application:

```bash
i=1; while [ $i -le 60 ]; do
  curl -kfsS "$url" >/dev/null && echo apiserver-ready && exit 0
  echo waiting... "$i/60"; i=$((i+1)); sleep 5
done; echo apiserver-not-ready >&2; exit 1
````

A cloud-init wait and AWS CLI polling loop gate the S3 artifact sync on the Docker server. These are explicit synchronization points. They fill the gap between what Terraform's dependency graph can represent and what the cluster actually requires.

---

## Artifact Correctness Failures

Artifacts may be structurally valid while semantically incorrect.

The artifact boundary guarantees that all required files exist and are structurally complete before execution. It does not guarantee semantic correctness, specifically whether values within those files are mutually consistent or valid for the target cluster's runtime behavior.

Examples:

* kubeconfigs referencing incorrect endpoints
* certificates missing required SAN entries
* CIDR ranges overlapping with underlying network topology

These conditions pass Terraform validation and are only detected at runtime when Kubernetes components attempt to consume them.

---

## Infrastructure Tooling Constraints

### Terraform Validation Limitations

Terraform `variable { validation { } }` blocks are limited to single-variable context and cannot express cross-variable structural constraints.

Cross-variable invariants, such as requiring an odd `controller_max >= 3` when `ha_enabled` is true, or requiring at least three AZs when HA is enabled, are enforced using `lifecycle { precondition }` blocks instead. These blocks can reference arbitrary combinations of variables and locals. The checks run at plan time and reject violating configurations before any resources are created.

Any invariants that cannot be expressed through either mechanism remain documented but unenforced.

---

## Implementation Complexity

These are design decisions that added development cost without proportional value. The system works correctly. These are cases where a simpler approach would have produced the same result with less friction.

### Inline Heredocs Instead of Template Files

All cluster configuration, including kubeconfigs, systemd units, CNI configuration, and encryption config, is generated as inline heredoc strings inside a single large Terraform locals block in `config_contents.tf`. Each artifact is an interpolated string embedded directly in the locals definition.

The cleaner approach would be Terraform template files: one `.tpl` file per artifact rendered via `templatefile()`. That would make each configuration artifact independently readable and editable, with proper syntax highlighting and without requiring changes to the locals block to modify a single field.

The current approach works but makes the file difficult to navigate and individual artifacts difficult to reason about in isolation. It also makes plan-time errors harder to attribute to a specific artifact. This would be the first thing refactored.

---

### Docker-on-VM Instead of Direct VM Execution

The goal was to avoid installing Ansible, kubectl, and Docker locally. The approach taken was to containerize Ansible and kubectl, provision a dedicated Docker VM to run them, and use a private registry running on that VM to manage image distribution. Terraform SSHs into the Docker VM to build, push, pull, and run containers as part of the services apply.

The Docker server is the root of a cascade of complexity that would not otherwise exist. It requires a private registry, an image build pipeline, push and pull machinery, and Terraform provider configuration that introduces a concrete technical constraint. The Docker provider must be initialized with the VM's public IP, which AWS only assigns after infrastructure apply. This is why the services root cannot be merged with the infrastructure root even if that were otherwise desirable. The two-root split is structurally sound, but the Docker server made it necessary.

The simpler path would have been a plain VM with Ansible and kubectl installed directly via a provisioner. The containerization added no meaningful capability. The mistake was not the original goal of avoiding local installations, but continuing with the Docker VM approach after it became more operationally expensive than installing Ansible and kubectl locally.

A plain VM with directly installed tools would have satisfied the same constraint, required none of the registry or image pipeline infrastructure, and left the two-root split as a deliberate architectural choice rather than a technical necessity.

---

## Failure Boundary Property

Failures are not eliminated. They are partially shifted earlier in the lifecycle through pre-execution validation and artifact inspection, but they remain present at runtime.

Runtime systems continue to produce failures independently of artifact correctness. The artifact layer exposes intended cluster state for pre-execution review and makes certain failure classes diagnosable without node inspection. It does not replace runtime verification or guarantee operational correctness.

---

## Known Limitations

### CA Private Key Storage

The cluster CA private key is stored in Terraform state and distributed as part of artifact generation. The blast radius of a compromised state file is full cluster compromise. An attacker with the CA private key can issue arbitrary certificates trusted by the cluster.

This is suitable only for deterministic reference infrastructure. See the [Design Rationale](design-rationale.md) for the production alternative.

---

### No Automated etcd Recovery

There is no automated recovery mechanism for etcd quorum loss after initial formation.

Recovery requires stopping etcd on all members, wiping data directories, and reinitializing. That procedure is outside the scope of this document.

---

## Scope

This document defines failure classes inherent to system structure and execution model.

It does not describe operational procedures or debugging methodology.