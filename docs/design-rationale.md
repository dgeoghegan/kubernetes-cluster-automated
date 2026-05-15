# Design Rationale - Kubernetes Cluster Automation

This document covers the architectural decisions in this project and where they actually came from. Where the motivation was operational pressure or learning-as-I-went rather than deliberate design, that's noted alongside the merits of the outcome.

---

## Terraform and Ansible

Terraform handles infrastructure provisioning and configuration rendering. Ansible handles distribution and service startup. That split reflects what each tool is actually designed to do.

Doing the whole thing in Terraform would have been a disaster. Terraform has no native concept of procedural sequencing, no retry logic, and no conditional execution based on runtime state. Bootstrap processes are inherently procedural: wait for this, then run that, handle this failure mode. Trying to orchestrate that in Terraform means abusing `null_resource` and `local-exec` provisioners, which I did plenty of before moving that logic somewhere more appropriate.

Ansible is the standard tool for procedural execution against live nodes. I'd never used it before starting this project, but it was the obvious choice.

---

## Terraform Rendering Configuration

Terraform generates certificates, kubeconfigs, systemd service units, etcd peer strings, and Ansible inventory, not just EC2 and networking. That wasn't a principled design decision upfront. I set out to use Terraform for everything because I was still learning the tool and didn't fully know its limitations. Terraform had the information needed to generate the files, so I had it generate them.

In retrospect, the approach is defensible even if the origin wasn't deliberate. The constraint that makes it work is Terraform's dependency graph. EC2 instance attributes such as IPs and DNS names only exist after instance creation. Terraform exposes those values within the same dependency graph, which means certificates and service definitions can reference live infrastructure values and be rendered in the same apply. That's the earliest point where they can be rendered correctly.

What the dependency graph enforces is ordering and completeness. If a certificate depends on an IP, the IP exists before the certificate is rendered. What it does not enforce is semantic correctness. Whether the certificate references that IP correctly is a function of whether the HCL is right. This is the same limitation described in the landing page: the artifact layer makes intended state inspectable, it does not make it correct.

One thing I'd do differently: the configuration rendering relies heavily on heredocs in local variables, which gets unwieldy. More templating and less heredoc would be cleaner.

---

## Ansible Is Execution-Only

Ansible does not template or synthesize configuration in this project. It copies artifacts, installs files, and starts services. All configuration generation stays in Terraform.

The honest origin of this constraint is that I hadn't used Ansible before and didn't know how to do templating with it. I started with Terraform, added Ansible later when I realized Terraform was bad at the things Ansible is designed for, and kept configuration generation where it already was.

The constraint turned out to be defensible regardless of how I got there. If Ansible can derive configuration at runtime, there are two places where config logic can live and diverge. When something breaks, you don't know whether the problem is in what Terraform generated or what Ansible derived at execution time. With Ansible execution-only, that ambiguity doesn't exist. If the config is wrong, it's wrong in the artifact, which is inspectable before anything runs.

The tradeoff is real: any configuration change requires a full Terraform apply to re-render, then an Ansible apply to redistribute. There is no safe path for runtime mutation. The Ansible `null_resource` also uses `always_run = timestamp()`, which means playbooks re-run on every services apply regardless of whether anything changed. This is safe because all service restarts are gated on file content changes. A re-run against an unchanged cluster copies identical files, registers no changes, and starts no services. But it means every apply takes the full Ansible execution time even when nothing has changed.

One exception: `kube-proxy.service` is defined inline in the playbook rather than rendered by Terraform and distributed via S3. It contains no node-specific values and doesn't affect the pre-execution artifact model, but it does break the "Ansible does not synthesize configuration" property in a narrow case. Everything else flows through Terraform.

Day-2 operations such as adding a worker or rotating a certificate require a Terraform apply to re-derive the artifact set followed by an Ansible apply to redistribute. The architecture was designed around bootstrap correctness. Day-2 operations work but were not the primary design target.

For the specific failure mode that reinforced the execution-only constraint, see [Failure Model](failure-model.md).

---

## The Management Script

The script started as a convenience wrapper for SSH access to the nodes because managing SSH through Terraform was cumbersome. But kubectl access and cluster SSH were intentional from early on, not afterthoughts. The K and S menu items reflect that the script was always intended as the operator interface into the cluster during development, not just an orchestration wrapper. As the project grew, it became the right place for the Terraform and Ansible orchestration logic I'd been misplacing elsewhere. Consolidating everything into one script also meant not having scattered entry points for different operations.

It sequences Terraform and Ansible execution phases, manages environment isolation, logs output, and handles SSH and kubectl access to nodes and runners. It is the only supported interface for provisioning, configuration distribution, and teardown.

One design choice worth noting: a single interactive menu rather than discrete CLI subcommands. That was a development convenience decision. The menu made sense for a tool I was building and using simultaneously. Concurrent execution is not guarded against. Two simultaneous runs against the same environment would produce unpredictable results. The script assumes a single operator.

---

## Containerized Runners

I wanted execution to be reproducible and free of local dependencies. Containers were the obvious answer. But I also didn't want Docker to be a local requirement, so I put Docker on an EC2 instance and ran the containers there.

Once Terraform started driving a remote Docker host, I ended up leaning heavily on `null_resource` and `local-exec` provisioners. Terraform isn't designed for procedural sequencing and I was pushing against that.

If I were building this again, I would just install Ansible and kubectl directly on the EC2 instance. Once Docker was already remote, containerizing the tooling stopped buying much. Containerization added a layer of complexity that the design didn't warrant. Setting up a registry for those containers didn't help.

**Security boundary:** The runner has SSH access to all cluster nodes and sits inside the same VPC. A compromised runner is a full cluster compromise. This project doesn't implement per-node key scoping or other lateral movement mitigations. That's a deliberate scope limitation for a lab environment, not an oversight. In a production deployment the runner would be a high-value target and would warrant tighter controls such as separate keys per node, instance profile scoping, or a bastion pattern.

Because the runner sits inside the VPC, it reaches the internal NLB directly. The Docker host is the network path for both Ansible and kubectl.

---

## Two Terraform Roots

The infrastructure and services roots started as one. The split was driven by a hard constraint: configuring the Docker registry required resolving information about the Docker server, but that information does not exist until after the server is created. Terraform provider configuration is evaluated before the resource graph executes, so the Docker provider could not be configured in the same root that defined the infrastructure.

Splitting into two roots solved that. Infrastructure applies first and writes its outputs to state. The services root reads those outputs via `remote_state`, which enforces a fixed ordering: infrastructure must complete before services can apply.

The separation is useful beyond that constraint. Infrastructure and services have different lifecycles. Networking and compute resources change less frequently than service configuration, so keeping them in separate roots means service configuration can be reapplied without touching infrastructure, and infrastructure can be inspected or recreated without affecting services.

One fragility worth noting: the `remote_state` path in the services root is hardcoded as a relative path to the infrastructure state file on disk. The management script's working directory isolation is what keeps that path valid. Running Terraform directly from an arbitrary directory would break it.

---

## HA Validation at Plan Time

Two HA constraints are enforced as Terraform validation blocks and preconditions: controller count must be odd and at least 3 when HA is enabled, and at least 3 AZs must support the requested instance type. Both fire before any resources are created.

The intent is the same as pre-execution artifact generation: surface errors as early as possible. A controller count violation caught at plan time costs nothing. The same violation caught at runtime, after EC2 instances are running and etcd fails to form quorum, costs time, money, and a teardown cycle.

The AZ check queries AWS at plan time via `data.aws_availability_zones`. That query reflects which AZs exist and are enabled, not whether instance capacity is actually available. Passing the precondition still doesn't guarantee the instance type actually has available capacity. That gap is documented in the failure model.

---

## The Role of S3

S3 sits between Terraform and Ansible. Terraform renders and uploads the artifact set. Ansible pulls from S3 rather than receiving files directly.

The operational property S3 provides is decoupling render from execute. Artifacts are independently inspectable before bootstrap begins. Reviewing the bucket shows exactly what configuration was distributed without requiring access to cluster nodes or execution logs. This follows the same principle as pre-execution artifact generation: you should be able to inspect what will be deployed before anything touches the cluster.

The artifact set is delivered via pull. A server bootstraps via `user_data`, installs dependencies including the AWS CLI, and pulls its configuration from S3 once readiness conditions are met. Re-synchronization is triggered by a hash of all artifact content, so Terraform detects changes to certificates or service definitions and marks the sync resource for re-execution on the next apply.

**Access control:** The IAM role grants `GetObject` and `ListBucket` only. That was a deliberate least-privilege decision.

**Security limitation:** The CA private key, all TLS private keys, and the cluster encryption key are generated by the Terraform `tls` provider and stored in plaintext in `terraform.tfstate`. This is a known anti-pattern. The blast radius of a compromised state file is full cluster compromise. An attacker with the CA private key can issue arbitrary certificates trusted by the cluster.

This was an acceptable tradeoff for a lab project. I wouldn't generate PKI material in Terraform for anything real. The CA would live in something like Vault or AWS Private CA, certificates would be issued via cert-manager or a similar in-cluster mechanism, and the Terraform state file would not contain private key material.

---

## Deterministic Private IP Assignment

Controllers are assigned private IPs at a fixed offset from the subnet base and workers at a different offset. This is not arbitrary.

The constraint traces directly from the configuration rendering approach. Certificates require SANs, and SANs require IPs. Because certificates are rendered during Terraform apply before bootstrap begins, the IPs have to be known at plan time. Letting DHCP assign IPs would mean IPs are only known after instance creation, which would require a second apply to render the certificates. That defeats the pre-execution artifact model.

Deterministic assignment via `cidrhost()` gives Terraform the IPs it needs to render correct certificates before bootstrap begins.

One undocumented constraint this creates: the scheme assumes at most 100 controllers and 100 workers per subnet. That's not a validated invariant anywhere in the code. It's an accidental limit that would silently produce incorrect IP assignments if exceeded. Worth documenting explicitly.