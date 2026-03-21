# Zero Trust Container Registry (ZTCR)

A production-grade, end-to-end zero trust container registry built entirely on open-source tools. Every image push, pull, and Kubernetes deployment is gated by identity — no anonymous access, no implicit trust.

## Architecture

```
Developer ──OIDC──► Keycloak ──JWT──► Harbor Registry
                        │
CI/CD Bot ──Robot──► Harbor ──Cosign──► Signed Image
                                              │
K8s Pod ──ServiceAccount──► Kyverno ◄─────────┘
                               │
                    ✅ Allow / ❌ Deny
```

## Stack

| Component | Role |
|---|---|
| [K3d](https://k3d.io) | K3s in Docker — local Kubernetes |
| [Harbor](https://goharbor.io) | Container registry with RBAC + vulnerability scanning |
| [Keycloak](https://www.keycloak.org) | OIDC Identity Provider |
| [Cosign](https://docs.sigstore.dev/cosign) | Image signing and verification |
| [Kyverno](https://kyverno.io) | Policy engine with native Cosign admission control |
| [Trivy](https://trivy.dev) | Vulnerability scanning (built into Harbor) |
| [Prometheus + Grafana](https://prometheus.io) | Observability and alerting |

> **Why Kyverno over OPA Gatekeeper?**
> Kyverno policies are pure Kubernetes YAML — no Rego, no extra language.
> It has native Cosign image verification built in: one `ClusterPolicy` enforces
> signed images without any sidecar or external webhook plumbing.

## Implementation Phases

| Phase | Topic | Status |
|---|---|---|
| [Phase 1](./phases/phase-1-infrastructure/) | Infrastructure Setup | 🔲 Not Started |
| [Phase 2](./phases/phase-2-keycloak/) | Keycloak Identity Provider | 🔲 Not Started |
| [Phase 3](./phases/phase-3-harbor/) | Harbor Registry + OIDC | 🔲 Not Started |
| [Phase 4](./phases/phase-4-cosign/) | Image Signing with Cosign | 🔲 Not Started |
| [Phase 5](./phases/phase-5-kyverno/) | Kyverno Policy Engine | 🔲 Not Started |
| [Phase 6](./phases/phase-6-admission-control/) | Admission Control via Kyverno | 🔲 Not Started |
| [Phase 7](./phases/phase-7-observability/) | Observability and Hardening | 🔲 Not Started |

## Local Environment

- **OS:** macOS (Apple Silicon or Intel)
- **Runtime:** Docker Desktop + K3d (K3s in Docker)
- **Domains:** `registry.ztcr.local`, `auth.ztcr.local`, `grafana.ztcr.local`
- **DNS:** `/etc/hosts` entries pointing to `127.0.0.1`

## Quick Start

```bash
# 1. Install tools
brew install k3d kubectl helm cosign

# 2. Create cluster
k3d cluster create ztcr-cluster \
  --servers 1 --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0" \
  --wait

# 3. Run Phase 1 bootstrap
cd phases/phase-1-infrastructure
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

→ Full guide: [Phase 1 README](./phases/phase-1-infrastructure/README.md)

## Repository Structure

```
zero-trust-container-registry/
├── README.md
├── .gitignore
├── docs/
│   └── architecture.md
└── phases/
    ├── phase-1-infrastructure/
    │   ├── README.md
    │   ├── scripts/
    │   │   └── bootstrap.sh
    │   └── manifests/
    │       ├── namespaces.yaml
    │       ├── cert-manager-issuer.yaml
    │       └── network-policies.yaml
    ├── phase-2-keycloak/          ← added in Phase 2
    ├── phase-3-harbor/            ← added in Phase 3
    ├── phase-4-cosign/            ← added in Phase 4
    ├── phase-5-kyverno/           ← added in Phase 5
    ├── phase-6-admission-control/ ← added in Phase 6
    └── phase-7-observability/     ← added in Phase 7
```
