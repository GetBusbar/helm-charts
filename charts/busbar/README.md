# busbar

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/busbar-helm-charts)](https://artifacthub.io/packages/search?repo=busbar-helm-charts)

A production-grade Helm chart for [busbar](https://getbusbar.com), a Rust LLM gateway.

busbar runs **two listeners**:

- **Data plane** (`0.0.0.0:8080`) — public LLM proxy traffic.
- **Admin plane** (`admin_listen`, default loopback `127.0.0.1:8081`) — the runtime admin API.

busbar has a **boot-guard**: a non-loopback `admin_listen` *refuses to boot* unless it requires
mTLS (`admin_tls` with a client CA) **or** `admin_insecure: true` is set. This chart honors that
guard — see [Admin plane](#admin-plane) below.

## Installing

```console
helm repo add busbar https://getbusbar.github.io/helm-charts
helm repo update
helm install my-busbar busbar/busbar -f my-values.yaml
```

`config` is **required and has no default.** busbar is a gateway in front of upstream LLM
providers, and it exits 1 at boot without a `providers` map
(`[error] config.yaml: invalid YAML: missing field 'providers'`), so there is no honest
zero-config default to ship: any "bootable" one would mean inventing credentials for an upstream
nobody configured. Installing with no `config` therefore **fails the render** and prints the
minimal config you need, instead of giving you a `CrashLoopBackOff`.

Everything else is secure by default: the admin plane stays on loopback and is not exposed, so the
admin boot-guard is satisfied out of the box.

```console
helm install my-busbar busbar/busbar -f - <<'EOF'
secrets:
  data:
    ANTHROPIC_KEY: sk-ant-...
    BUSBAR_ADMIN_TOKEN: a-long-random-admin-token
config:
  identity-providers:
    admin-tokens:
      module: admin-tokens
      token: { env: BUSBAR_ADMIN_TOKEN }
  auth:
    chain: []
    admin_auth: [admin-tokens]
  providers:
    anthropic:
      api_key: { env: ANTHROPIC_KEY }
  models:
    claude:
      provider: anthropic
  pools:
    default:
      members:
        - model: claude
EOF
```

Secrets are injected as environment variables from a Kubernetes Secret and referenced from the
config by **secret reference** (`api_key: { env: ANTHROPIC_KEY }`) - busbar 1.5.x removed the old
`*_env` string fields. The provider catalog ships inside the image at `/etc/busbar/providers.yaml`;
only set `providersCatalog` to override it.

`auth.chain: []` is an **open relay** and is for a first boot only; configure a real auth chain
before you expose the data plane.

## Config mutability

busbar 1.5.3 **refuses to boot** a mutable config (`config.locked: false`, its default) whose
overlay backend is not writable, and that backend defaults to `busbar-overlay.json` next to the
resolved `config.yaml` - here, `/etc/busbar/busbar-overlay.json`, which is a read-only ConfigMap
mount under `readOnlyRootFilesystem: true`:

```
[error] config is mutable (config.locked: false) but the overlay backend
'/etc/busbar/busbar-overlay.json' is not writable (is the config directory read-only?).
```

So the chart manages this for you via `configMutability.mode`:

| mode | renders | meaning |
|---|---|---|
| `locked` (default) | `config: { locked: true }` | The ConfigMap is the source of truth. The admin API refuses **config mutations** (it still serves keys, stats, `/config/reload` and the rest); you change config with `helm upgrade`, and `reloadOnConfigChange` rolls the pods. |
| `overlay` | `config: { locked: false, overlay: { file: <overlayFile> } }` | Admin-API config mutation works again, persisted to `configMutability.overlayFile` (default `/tmp/busbar-overlay.json`, on the chart's emptyDir). |
| `none` | nothing | You own `config.locked` / `config.overlay` inside `.Values.config`. |

`locked` is the default because a Helm release **is** a GitOps deployment, and because it is the
only mode that is correct at `replicaCount > 1`. In `overlay` mode with the default path the
overlay lives on a per-pod `emptyDir`: mutations are lost on restart, on `helm upgrade` and on any
reschedule, and with more than one replica **each replica keeps its own overlay and the replicas
will diverge**. Use `overlay` at `replicaCount: 1`, or point `overlayFile` at durable storage that
every replica mounts read-write.

Anything you set under `.Values.config.config` wins over the chart's value in every mode.

## Admin plane

The admin plane is **not exposed** by default. To reach it cluster-wide, set
`service.admin.enabled=true` — which binds `admin_listen: 0.0.0.0:8081`. Because of the boot-guard
you must ALSO enable one of:

- `adminTLS.enabled=true` (recommended — mTLS, ideally via cert-manager), or
- `adminInsecure=true` (insecure waiver; pair with a `NetworkPolicy`).

If you enable the admin Service without either, the chart **fails the render** with a clear message.

## Governance

When `governance.enabled=true`, busbar owns single-writer state, so the chart switches to a
**StatefulSet with a PVC and `replicas: 1`**. **Horizontal scale of a shared single-writer store is
not supported.** Stateless (no governance) deployments use a Deployment and may scale out (HPA
supported).

busbar 1.5.x dissolved the old top-level `governance:` config block (it is now a hard 1.x marker
the binary refuses to boot) into `store:` plus an admin-tokens identity provider referenced from
`auth.admin_auth`. The chart renders that shape for you.

Every durable store in 1.5.x is a signed **store** plugin, and the `getbusbar/busbar:1.5.3` image
ships no plugin tarballs (`busbar --list-plugins` prints `no plugin tarballs found`), so
`governance.store.module` defaults to `memory`: keys, group usage and ledgers are **ephemeral** and
reset on restart. To get durability, mount the signed store plugin into the pod yourself, set
`config.plugins.enabled: true` and `config.plugins.dir`, then set `governance.store.module`. The
chart fails the render if you name a non-`memory` module without wiring the plugin, because busbar
would otherwise exit 1.

## Examples

### Minimal (default, admin on loopback)

```yaml
secrets:
  data:
    ANTHROPIC_KEY: sk-ant-...
    BUSBAR_ADMIN_TOKEN: a-long-random-admin-token
config:
  identity-providers:
    admin-tokens:
      module: admin-tokens
      token: { env: BUSBAR_ADMIN_TOKEN }
  auth:
    chain: []                 # open relay; set a real chain before exposing the data plane
    admin_auth: [admin-tokens]
  providers:
    anthropic:
      api_key: { env: ANTHROPIC_KEY }
  models:
    claude:
      provider: anthropic
  pools:
    default:
      members:
        - model: claude       # `model:`, not the retired 1.4.x `target:`
```

### With governance

Governance requires an admin token: put it in `secrets.data` under the key named by
`governance.adminTokenEnv` (default `BUSBAR_ADMIN_TOKEN`); the chart wires
`identity-providers.admin-tokens` and `auth.admin_auth` for you. (`helm install` fails fast if it
is missing.)

```yaml
governance:
  enabled: true
  store:
    module: memory            # see the note above about durable store plugins
  dbPath: /var/lib/busbar/governance.db
  persistence:
    size: 5Gi
    storageClass: fast-ssd
secrets:
  data:
    ANTHROPIC_KEY: sk-ant-...
    BUSBAR_ADMIN_TOKEN: super-secret-admin-token
config:
  providers:
    anthropic:
      api_key: { env: ANTHROPIC_KEY }
  models:
    claude:
      provider: anthropic
  pools:
    default:
      members:
        - model: claude
```

### With ingress (data plane)

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: gw.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: gw-tls
      hosts:
        - gw.example.com
```

### With admin mTLS (cert-manager)

```yaml
service:
  admin:
    enabled: true
adminTLS:
  enabled: true
  certManager:
    enabled: true
    issuerRef:
      name: busbar-ca
      kind: ClusterIssuer
  clientCASecret: busbar-admin-client-ca   # Secret with ca.crt the admin clients chain to
networkPolicy:
  enabled: true
  admin:
    allowedNamespaces:
      - platform-ops
```

## Values

| Key | Description | Default |
|---|---|---|
| `image.repository` | Image repository | `getbusbar/busbar` |
| `image.tag` | Image tag (falls back to `.Chart.AppVersion`) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Pull secrets for private registries | `[]` |
| `nameOverride` | Override the chart name | `""` |
| `fullnameOverride` | Override the full resource name | `""` |
| `replicaCount` | Replicas (stateless mode) | `1` |
| `serviceAccount.create` | Create a ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount name | `""` |
| `serviceAccount.annotations` | ServiceAccount annotations | `{}` |
| `podAnnotations` | Pod annotations | `{}` |
| `podSecurityContext` | Pod security context | hardened (non-root, RuntimeDefault) |
| `securityContext` | Container security context | hardened (RO rootfs, drop ALL) |
| `resources` | Resource requests/limits | see values.yaml |
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Tolerations | `[]` |
| `affinity` | Affinity | `{}` |
| `config` | **Required.** Structured map rendered to `config.yaml` (chart injects `listen`/`admin_listen`) | `{}` (fails the render) |
| `configMutability.mode` | `locked` / `overlay` / `none` (see [Config mutability](#config-mutability)) | `locked` |
| `configMutability.overlayFile` | Overlay backend path, `overlay` mode only. Pod-local and ephemeral by default | `/tmp/busbar-overlay.json` |
| `providersCatalog` | Optional map rendered to `providers.yaml` (else the image's catalog is used) | `{}` |
| `existingConfigMap` | Use an existing ConfigMap instead of rendering config | `""` |
| `secrets.create` | Create a Secret from `secrets.data` | `true` |
| `secrets.existingSecret` | Use an existing Secret | `""` |
| `secrets.data` | Key/value secret data injected as env vars | `{}` |
| `governance.enabled` | Enable governance (StatefulSet + PVC, replicas=1) | `false` |
| `governance.adminTokenEnv` | Secret key holding the admin token | `BUSBAR_ADMIN_TOKEN` |
| `governance.store.module` | `store:` module. Non-`memory` needs a signed store plugin you supply | `memory` |
| `governance.dbPath` | Governance DB path (`store.settings.db_path`, non-`memory` only) | `/var/lib/busbar/governance.db` |
| `governance.persistence.size` | Governance PVC size | `1Gi` |
| `governance.persistence.storageClass` | Governance PVC storage class | `""` |
| `governance.persistence.accessMode` | Governance PVC access mode | `ReadWriteOnce` |
| `service.data.type` | Data Service type | `ClusterIP` |
| `service.data.port` | Data Service port | `8080` |
| `service.data.annotations` | Data Service annotations | `{}` |
| `service.admin.enabled` | Expose the admin plane via a Service | `false` |
| `service.admin.type` | Admin Service type | `ClusterIP` |
| `service.admin.port` | Admin Service port | `8081` |
| `adminTLS.enabled` | Terminate mTLS on the admin listener | `false` |
| `adminTLS.certManager.enabled` | Issue the admin cert via cert-manager | `false` |
| `adminTLS.certManager.issuerRef.name` | cert-manager issuer name | `""` |
| `adminTLS.certManager.issuerRef.kind` | cert-manager issuer kind | `Issuer` |
| `adminTLS.existingSecret` | Existing admin server cert Secret | `""` |
| `adminTLS.clientCASecret` | Secret with client CA bundle (`ca.crt`) for mTLS | `""` |
| `adminInsecure` | Non-loopback admin bind without mTLS (insecure waiver) | `false` |
| `dataTLS.enabled` | Terminate TLS on the data listener | `false` |
| `dataTLS.existingSecret` | Existing data TLS cert Secret | `""` |
| `ingress.enabled` | Create a data-plane Ingress | `false` |
| `ingress.className` | IngressClass name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts | `[]` |
| `ingress.tls` | Ingress TLS config | `[]` |
| `networkPolicy.enabled` | Create a NetworkPolicy | `false` |
| `networkPolicy.admin.allowedNamespaces` | Namespaces allowed to reach the admin plane | `[]` |
| `autoscaling.enabled` | Enable an HPA (data Deployment only) | `false` |
| `autoscaling.minReplicas` | HPA min replicas | `1` |
| `autoscaling.maxReplicas` | HPA max replicas | `5` |
| `autoscaling.targetCPUUtilizationPercentage` | HPA target CPU | `80` |
| `podDisruptionBudget.enabled` | Create a PodDisruptionBudget | `false` |
| `podDisruptionBudget.minAvailable` | PDB minAvailable | `1` |
| `reloadOnConfigChange` | Roll pods on config/secret change (checksum) | `true` |
