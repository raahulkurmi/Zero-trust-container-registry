# Zero Trust Container Registry (ZTCR)

A production-grade, end-to-end implementation of a zero trust container registry on Kubernetes. Every image push, pull, and deployment is gated by identity — no anonymous access, no implicit trust.

![Architecture](docs/architecture.png)

## Stack

| Component | Role | Version |
|---|---|---|
| **K3d** | Lightweight Kubernetes (local) | v1.33.6 |
| **Harbor** | Container Registry | v2.14.3 |
| **Keycloak** | Identity Provider (OIDC) | v26.0.0 |
| **Cosign** | Image Signing & Verification | v3.0.5 |
| **Kyverno** | Kubernetes Policy Engine | v1.17.1 |
| **Trivy** | Vulnerability Scanning (built into Harbor) | latest |
| **cert-manager** | TLS Certificate Management | v1.x |
| **NGINX Ingress** | Ingress Controller | latest |

---

## What is Zero Trust?

Traditional security: "Everything inside the network is trusted."

Zero Trust: "Never trust, always verify — regardless of where the request comes from."

In container registry context:
- Every human login goes through Keycloak OIDC — no local passwords
- Every CI/CD pipeline uses scoped robot accounts — least privilege
- Every image is cryptographically signed with Cosign — no unsigned images run
- Every image is scanned by Trivy — no HIGH/CRITICAL CVEs allowed
- Every Kubernetes pod is validated by Kyverno — policy as code

---

## Architecture

```
Developer
    │ OIDC login
    ▼
Keycloak (Identity Provider)
    │ JWT with groups claim
    ▼
Harbor (Container Registry)
    │ RBAC based on groups
    ├── team-alpha project
    └── team-beta project
         │
         │ Trivy scans every image
         │ Cosign signs every image
         ▼
Kubernetes (K3d)
    │
    ▼
Kyverno (Admission Controller)
    ├── Block :latest tag
    ├── Block non-approved registry
    └── Block unsigned images
         │
         ▼
    Pod runs ✅ or blocked ❌
```

---

## Zero Trust Decision Points

| Action | Who | How |
|---|---|---|
| Push image | CI/CD robot account | Harbor RBAC |
| Scan image | Trivy | Auto-scan on push |
| Sign image | Cosign private key | CI/CD pipeline |
| Pull image (human) | Keycloak OIDC | JWT groups claim |
| Pull image (K8s) | imagePullSecret | Robot account per namespace |
| Deploy pod | Kyverno | Policy enforcement |

---

## Project Structure

```
zero-trust-container-registry/
├── phases/
│   ├── phase-1-infrastructure/
│   │   ├── manifests/
│   │   │   ├── namespaces.yaml
│   │   │   ├── cert-manager-issuer.yaml
│   │   │   └── network-policies.yaml
│   │   └── scripts/
│   │       └── bootstrap.sh
│   ├── phase-2-keycloak/
│   │   ├── manifests/
│   │   │   ├── keycloak-deployment.yaml
│   │   │   ├── keycloak-postgres.yaml
│   │   │   ├── keycloak-ingress.yaml
│   │   │   └── keycloak-tls.yaml
│   │   └── scripts/
│   │       └── setup-keycloak.sh
│   ├── phase-3-harbor/
│   │   ├── harbor-values.yaml
│   │   ├── manifests/
│   │   │   └── harbor-tls.yaml
│   │   └── scripts/
│   │       └── setup-harbor.sh
│   ├── phase-4-cosign/
│   │   └── keys/
│   │       └── cosign.pub   ← public key only (private key in .gitignore)
│   ├── phase-5-kyverno/
│   │   └── policies/
│   │       ├── block-latest-tag.yaml
│   │       ├── require-approved-registry.yaml
│   │       └── require-signed-images.yaml
│   └── phase-6-observability/
│       └── monitoring-values.yaml
├── docs/
│   └── architecture.md
├── PROGRESS.md
├── .gitignore
└── README.md
```

---

## Quick Start

### Prerequisites
- macOS with Docker Desktop (8GB+ RAM)
- `k3d`, `kubectl`, `helm`, `cosign` installed

```bash
brew install k3d kubectl helm cosign
```

### 1. Create Cluster

```bash
k3d cluster create ztcr-cluster \
  --servers 1 --agents 2 \
  --port "8443:443@loadbalancer" \
  --port "8080:80@loadbalancer"
```

### 2. Add DNS entries

```bash
echo "127.0.0.1 auth.ztcr.local registry.ztcr.local grafana.ztcr.local" | sudo tee -a /etc/hosts
```

### 3. Run Phase 1 bootstrap

```bash
chmod +x phases/phase-1-infrastructure/scripts/bootstrap.sh
./phases/phase-1-infrastructure/scripts/bootstrap.sh
```

### 4. Deploy Keycloak

```bash
kubectl apply -f phases/phase-2-keycloak/manifests/keycloak-postgres.yaml
kubectl apply -f phases/phase-2-keycloak/manifests/keycloak-deployment.yaml
kubectl apply -f phases/phase-2-keycloak/manifests/keycloak-ingress.yaml
./phases/phase-2-keycloak/scripts/setup-keycloak.sh
```

### 5. Deploy Harbor

```bash
helm upgrade --install harbor harbor/harbor \
  --namespace registry \
  -f phases/phase-3-harbor/harbor-values.yaml
./phases/phase-3-harbor/scripts/setup-harbor.sh
```

### 6. Sign an image

```bash
docker push registry.ztcr.local:8443/team-alpha/my-app:v1
cosign sign --key phases/phase-4-cosign/keys/cosign.key \
  registry.ztcr.local:8443/team-alpha/my-app:v1
```

### 7. Apply Kyverno policies

```bash
kubectl apply -f phases/phase-5-kyverno/policies/
```

---

## Kyverno Policies in Action

### Block :latest tag
```bash
kubectl run test --image=nginx:latest -n team-alpha
# Error: :latest tag is not allowed. Use a specific version tag.
```

### Block unauthorized registry
```bash
kubectl run test --image=docker.io/nginx:1.25 -n team-alpha
# Error: Images must be from registry.ztcr.local:8443 only.
```

### Block unsigned images
```bash
kubectl run test --image=registry.ztcr.local:8443/team-alpha/unsigned:v1 -n team-alpha
# Error: Image signature verification failed.
```

---

## Robot Account Strategy

| Robot | Namespace | Permissions |
|---|---|---|
| `robot$team-alpha+team-alpha-ci` | team-alpha | push + pull |
| `robot$team-alpha+team-alpha-argocd` | team-alpha | pull only |
| `robot$team-beta+team-beta-ci` | team-beta | push + pull |

### Attach to Kubernetes namespace

```bash
kubectl create secret docker-registry harbor-pull-secret \
  --namespace team-alpha \
  --docker-server=registry.ztcr.local:8443 \
  --docker-username="robot\$team-alpha+team-alpha-argocd" \
  --docker-password="<SECRET>"

kubectl patch serviceaccount default \
  --namespace team-alpha \
  -p '{"imagePullSecrets": [{"name": "harbor-pull-secret"}]}'
```

---

## Lessons Learned

- **Keycloak H2 database** loses data on restart — always use PostgreSQL in production
- **Port mismatch**: K3d exposes `:8443` externally but internally NGINX listens on `:443` — CoreDNS customhosts needed
- **CA trust**: Every component (Harbor, Kyverno) needs the self-signed CA mounted explicitly
- **Kyverno image verification** requires registry to be reachable from within the cluster on the same port as the image reference
- **OIDC issuer** must match exactly — `KC_HOSTNAME` + `KC_HOSTNAME_PORT` must align with what Harbor expects

---

## License

MIT
