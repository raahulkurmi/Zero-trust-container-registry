# Architecture — Zero Trust Container Registry

## Core Principle

Every actor (human, CI/CD bot, Kubernetes workload) must **authenticate and be authorized** before interacting with the registry. There is no anonymous access, no implicit network trust.

## Zero Trust Decision Points

```
PUSH
  └── Who are you?            → OIDC token issued by Keycloak
  └── Can you push here?      → Harbor RBAC (project membership)
  └── Is your image clean?    → Trivy scan (block on HIGH/CRITICAL)

PULL
  └── Who are you?            → OIDC token or Kubernetes ServiceAccount
  └── Can you pull this?      → Harbor RBAC

DEPLOY (Kubernetes admission via Kyverno)
  └── Is it signed?           → Kyverno ClusterPolicy: verify-image-signature
  └── From approved registry? → Kyverno ClusterPolicy: restrict-image-registries
  └── No :latest tag?         → Kyverno ClusterPolicy: disallow-latest-tag
  └── Has required labels?    → Kyverno ClusterPolicy: require-labels
```

## Why Kyverno (not OPA Gatekeeper)

| | Kyverno | OPA Gatekeeper |
|---|---|---|
| Policy language | Kubernetes YAML | Rego (separate DSL) |
| Native Cosign image verification | ✅ Built-in | ❌ Requires manual webhook setup |
| Learning curve | Low | High |
| Mutation support | ✅ Yes | Limited |
| Generate resources | ✅ Yes | ❌ No |
| Audit mode | ✅ Yes | ✅ Yes |

## Full Component Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                          MacBook (Dev)                           │
│                                                                  │
│   docker push/pull ─────────────────────────────────────────┐   │
│   kubectl apply    ─────────────────────────────────────┐   │   │
│                                                         │   │   │
└─────────────────────────────────────────────────────────┼───┼───┘
                                                          │   │
                                                   K3d Cluster
┌─────────────────────────────────────────────────────────┼───┼───┐
│                                                         │   │   │
│  ┌──────────────────┐   OIDC/JWT   ┌────────────────┐  │   │   │
│  │    Keycloak       │◄─────────────│     Harbor     │◄─┼───┘   │
│  │  (identity ns)    │   validate   │  (registry ns) │  │       │
│  └──────────────────┘              └───────┬────────┘  │       │
│                                            │            │       │
│                                     Cosign │ sign/store │       │
│                                            ▼            │       │
│  ┌──────────────────┐              ┌────────────────┐   │       │
│  │     Kyverno       │             │  Trivy Scanner │   │       │
│  │   (kyverno ns)    │             │  (in Harbor)   │   │       │
│  │                   │             └────────────────┘   │       │
│  │ Policies:         │                                   │       │
│  │  verify-signature │                                   │       │
│  │  restrict-registr │                                   │       │
│  │  disallow-latest  │                                   │       │
│  │  require-labels   │                                   │       │
│  └────────┬──────────┘                                   │       │
│           │ admit / deny                                 │       │
│           ▼                                              │       │
│  ┌────────────────────────────────────────────────────┐  │       │
│  │             Workload Namespaces                    │◄─┘       │
│  │         (team-alpha, team-beta, ...)               │          │
│  └────────────────────────────────────────────────────┘          │
│                                                                   │
│  ┌────────────────────────────────────────────────────┐          │
│  │            Monitoring  (monitoring ns)              │          │
│  │          Prometheus ◄──────── Grafana               │          │
│  └────────────────────────────────────────────────────┘          │
└───────────────────────────────────────────────────────────────────┘
```

## Namespace Security Zones

| Namespace | Zone | What lives here |
|---|---|---|
| `identity` | internal | Keycloak — OIDC provider for all components |
| `registry` | internal | Harbor — image storage, RBAC, Trivy scanning |
| `kyverno` | system | Kyverno — admission webhook and policy engine |
| `monitoring` | internal | Prometheus, Grafana, alert manager |
| `team-alpha` | workload | Example team — isolated, default-deny ingress |
| `team-beta` | workload | Example team — isolated, default-deny ingress |

## TLS Strategy

A single local root CA (`ztcr-ca-issuer`) signs all service certificates. Trust this one CA on your Mac and Docker client — all HTTPS endpoints (Harbor, Keycloak, Grafana) will be trusted automatically.

## OIDC Authentication Flow

```
1. Developer: docker login registry.ztcr.local
2. Harbor redirects to Keycloak login page
3. Developer authenticates with Keycloak credentials
4. Keycloak issues JWT (access token + id token with group claims)
5. Harbor validates JWT against Keycloak JWKS endpoint
6. Harbor maps group claims → project roles/permissions
7. Push or pull proceeds — or is denied
```

## Image Signing + Enforcement Flow

```
1. CI/CD builds image → pushes to Harbor
2. Cosign signs the image digest with private key
3. Signature stored as OCI artifact in Harbor alongside the image

On every kubectl apply / pod creation:
4. Kyverno admission webhook intercepts the request
5. ClusterPolicy: verify-image-signature
   → fetches image digest from Harbor
   → looks up Cosign signature in Harbor OCI store
   → verifies signature against the stored public key
6. ✅ Signature valid   → pod admitted
   ❌ No / bad signature → pod rejected with clear error message
```

## Kyverno Policies Summary (Phases 5 & 6)

| Policy name | Type | Enforces |
|---|---|---|
| `verify-image-signature` | Validation | All images must be Cosign-signed |
| `restrict-image-registries` | Validation | Images must come from `registry.ztcr.local` only |
| `disallow-latest-tag` | Validation | `:latest` tag is blocked — use digest or semver |
| `require-labels` | Validation | All pods must have `app` and `team` labels |
| `add-default-securitycontext` | Mutation | Auto-inject `runAsNonRoot: true` if missing |
