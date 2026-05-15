# Kubernetes Cluster Automation

This project automates [Kubernetes The Hard Way (AWS)](https://github.com/prabhatsharma/kubernetes-the-hard-way-aws.git) using Terraform and Ansible.

I built this after failing to get the manual tutorial working reliably. Kubernetes The Hard Way is a step-by-step walkthrough of manual cluster construction using sequential shell commands. The "truth" of the cluster is distributed across environment variables, local files, and node-level state generated at runtime. When my smoke tests failed, I had no clear way to see where things had diverged. Diagnosing meant SSHing across nodes, comparing generated files, and reconstructing the execution history. 

My bigger motivation, though, was sheer frustration at a mostly manual process crying out to be automated. Also, I didn't like that cluster size was fixed and a "high availability" control plane was set in a single availability zone. 

I didn't set out with a clean architecture in mind. I was trying to make debugging tractable while iterating on a fragile bootstrap process. The structure that emerged reflects that operational pressure.

---

## How the System is Structured

Automating this for HA and configurability meant doing more than scripting the manual steps in sequence. Node counts, subnet allocation, IP assignments, etcd peer topologies, and certificate SANs all need to be created dynamically. Instead of relying on values preselected by a tutorial author, correctly generating the configuration files now requires having a globally consistent map of the entire cluster's intended state.

With Terraform resolving those dependencies up front, the system forces a clean break: The full configuration is rendered before bootstrap begins, stored as artifacts, and consumed by the execution layer.

Five components carry distinct responsibilities:

- **Terraform:** Provisions the infrastructure and calculates the topology based on input. Handles the networking layout, spins up the EC2 instances, and pulls network attributes (IPs, DNS names) directly into its dependency graph so it can render the node certificates and systemd service units.

- **S3:** Stores the rendered configuration artifacts produced by Terraform.

- **Ansible:** Installs software components, distributes the configuration files, and starts services. It does not modify any configurations. 

- **Containerized runners:** Run Ansible and kubectl on a separate EC2 instance, providing a reproducible execution environment. The local workstation needs only git, Terraform, and AWS keys.

- **Bash management script:** Orchestrates the other tools and acts as the primary entry point. Sequences execution phases, manages environment isolation, logs output, and manages SSH access to nodes and runners. 

References: [Design Rationale](docs/design-rationale.md), [Artifact Schema](docs/artifact-schema.md)

---

## Topology Derivation

The original tutorial assumes a fixed number of servers in a single Availability Zone. Supporting HA and configurable cluster size required making topology derivation explicit.

Given desired controller count, worker count, instance requirements, and HA mode, Terraform:

- Queries which AZs support the requested instance types.
- Distributes nodes across available zones.
- Derives CIDR allocation, node naming, and etcd peer topology from the same model.
- Rejects configurations that violate HA constraints (odd controller count ≥ 3) before any resources are created.

---

## What This Doesn't Solve

The operational complexity of the manual bootstrap was formalized instead of being eliminated.

- Sequencing and timing between commands move from human wait time to readiness checks in the orchestration script and the Terraform modules.
- The topology still needs to be fully mapped before configurations can include the correct settings, but now that mapping is dynamically derived instead of being predefined by the tutorial author and therefore cumbersome to reconfigure.
- There is still no guarantee that the configurations work even if they're formed correctly. A kubeconfig referencing the wrong endpoint or a certificate missing a required SAN can pass Terraform validation then fail at runtime. Validating and testing the configuration semantics is now done in a codebase instead of by confirming a set of manual steps.
- Tearing down and rebuilding a cluster is still delicate, but of course now the process is automated.

The points of failure moved but they didn't disappear. The artifact layer makes the intended state inspectable earlier; it does not make it correct.

For a look at other problems either unsolved or introduced by this approach, see the [Failure Model](docs/failure-model.md).

---

## Tracking Down a Root Cause: etcd Quorum Formation

etcd is where bootstrap correctness depends on global consistency. A single mismatch in any of several configurations across all of the control-plane nodes prevents quorum formation, producing a silent failure mode where nodes wait indefinitely.

In manual bootstrap workflows, this consistency is only verified at runtime. Failures require reconstructing state across multiple nodes via SSH.

With the tools in this project, the full etcd topology and certificate configuration is rendered as part of the pre-execution artifact set. Inconsistencies are inspectable in a single place before bootstrap succeeds or fails.

---

## Verification

The supporting documentation includes verification scripts you can run against the repository to confirm that the structural claims hold in the current codebase without spinning up a cluster.

→ [Verification Walkthrough](docs/claim-verification.md)

---

## Getting Started

If you do want to provision and interact with this system, though, refer to the [Setup Guide](SETUP_GUIDE.md).