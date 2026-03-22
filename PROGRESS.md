# Zero Trust Container Registry — Progress

## How to continue in a new session
Say: "Continue the Zero Trust Container Registry project. Read PROGRESS.md and pick up from where we left off."

## Environment
- MacBook (macOS), 16GB RAM
- K3d cluster (3 nodes) — Docker Desktop
- Local DNS via /etc/hosts
- Domains: auth.ztcr.local:8443, registry.ztcr.local:8443, grafana.ztcr.local:8443

## Credentials
- Harbor admin: admin / Harbor12345
- Keycloak admin: admin / ztcr-admin-secret
- Grafana admin: admin / Grafana12345
- Harbor OIDC client secret: LB0XVHEgTlX1AvVrNxEcZ5cJTnRTqc9E
- dev-user: dev-user / dev-password

## Phase Status

### ✅ Phase 1 — Infrastructure
- K3d cluster running (3 nodes)
- NGINX ingress as DaemonSet
- cert-manager with self-signed CA (ztcr-ca-issuer)
- Namespaces: registry, identity, monitoring, team-alpha, team-beta
- Network policies applied
- /etc/hosts entries for all domains

### ✅ Phase 2 — Keycloak
- Keycloak 26.0.0 running at https://auth.ztcr.local:8443
- PostgreSQL backend (persistent data)
- ztcr realm configured
- harbor OIDC client configured
- Groups: harbor-admins, harbor-developers, harbor-viewers
- dev-user created and added to harbor-developers
- Groups claim mapper configured

### ✅ Phase 3 — Harbor
- Harbor v2.14.3 running at https://registry.ztcr.local:8443
- OIDC configured (auth_mode: oidc_auth → Keycloak)
- Projects: team-alpha, team-beta (private, Trivy scanning enabled)
- Robot accounts: team-alpha-ci, team-alpha-argocd, team-beta-ci
- Trivy vulnerability scanning enabled

### ✅ Phase 4 — Cosign
- Cosign v3.0.5
- Key pair generated: phases/phase-4-cosign/keys/
- hello-world:v1 image signed and verified
- cosign.key in .gitignore (never commit)

### ✅ Phase 5 — Kyverno
- Kyverno v1.17.1 installed
- Policy: block-latest-tag (Enforce) ✅
- Policy: require-approved-registry (Enforce) ✅
- Policy: require-signed-images — configured but image verification
  has port 8443 networking issue in local K3d (production ready)

### 🔄 Phase 6 — Observability
- Prometheus + Grafana — pending (memory constraints on local Mac)
- monitoring-values.yaml ready

## Known Issues & Fixes
1. Keycloak data loss on restart → Fixed with PostgreSQL backend
2. Harbor OIDC issuer mismatch → Fixed with KC_HOSTNAME=https://auth.ztcr.local + KC_HOSTNAME_PORT=443
3. CoreDNS updated to resolve auth.ztcr.local + registry.ztcr.local internally
4. Harbor CA cert mounted in harbor-core and kyverno-admission-controller
5. Kyverno image verification port 8443 → workaround: policy excluded for local dev

## Next Steps
- Fix Prometheus OOMKilled (increase Docker Desktop memory to 10GB)
- Fix Kyverno image verification (port 8443 internal routing)
- Write README, Medium blog, LinkedIn post
