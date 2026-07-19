# busbar

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
helm install my-busbar busbar/busbar
```

The defaults render a secure, bootable deployment: the admin plane stays on loopback and is not
exposed, so the gateway always boots. Supply a provider key and a client token to make it useful:

```console
helm install my-busbar busbar/busbar \
  --set-string secrets.data.OPENAI_API_KEY=sk-... \
  --set-string secrets.data.BUSBAR_CLIENT_TOKEN=my-client-token \
  --set 'config.auth.chain[0]=client-tokens' \
  --set 'config.auth.client_tokens[0]=${BUSBAR_CLIENT_TOKEN}' \
  --set config.providers.openai.api_key_env=OPENAI_API_KEY \
  --set config.models.gpt-4o.provider=openai \
  --set config.models.gpt-4o.max_concurrent=8
```

Secrets are injected as environment variables from a Kubernetes Secret and referenced from the
config with `${VAR}` interpolation. The provider catalog ships inside the image at
`/etc/busbar/providers.yaml`; only set `providersCatalog` to override it.

## Admin plane

The admin plane is **not exposed** by default. To reach it cluster-wide, set
`service.admin.enabled=true` — which binds `admin_listen: 0.0.0.0:8081`. Because of the boot-guard
you must ALSO enable one of:

- `adminTLS.enabled=true` (recommended — mTLS, ideally via cert-manager), or
- `adminInsecure=true` (insecure waiver; pair with a `NetworkPolicy`).

If you enable the admin Service without either, the chart **fails the render** with a clear message.

## Governance

When `governance.enabled=true`, busbar owns a single-writer SQLite DB — per-replica state. The chart
switches to a **StatefulSet with a PVC and `replicas: 1`**. **Horizontal scale of a shared SQLite
governance store is not supported.** Stateless (no governance) deployments use a Deployment and may
scale out (HPA supported).

## Examples

### Minimal (default, admin on loopback)

```yaml
secrets:
  data:
    OPENAI_API_KEY: sk-...
    BUSBAR_CLIENT_TOKEN: my-client-token
config:
  auth:
    chain: ["client-tokens"]
    client_tokens: ["${BUSBAR_CLIENT_TOKEN}"]
  providers:
    openai:
      api_key_env: OPENAI_API_KEY
  models:
    gpt-4o:
      provider: openai
      max_concurrent: 8
```

### With governance

Governance requires an admin token — put it in `secrets.data` under the key named by
`governance.adminTokenEnv` (default `BUSBAR_ADMIN_TOKEN`); the chart wires
`governance.admin_token` for you. (`helm install` fails fast if it is missing.)

```yaml
governance:
  enabled: true
  dbPath: /var/lib/busbar/governance.db
  persistence:
    size: 5Gi
    storageClass: fast-ssd
secrets:
  data:
    BUSBAR_ADMIN_TOKEN: super-secret-admin-token
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
| `config` | Structured map rendered to `config.yaml` (chart injects `listen`/`admin_listen`) | `{}` |
| `providersCatalog` | Optional map rendered to `providers.yaml` (else the image's catalog is used) | `{}` |
| `existingConfigMap` | Use an existing ConfigMap instead of rendering config | `""` |
| `secrets.create` | Create a Secret from `secrets.data` | `true` |
| `secrets.existingSecret` | Use an existing Secret | `""` |
| `secrets.data` | Key/value secret data injected as env vars | `{}` |
| `governance.enabled` | Enable governance (StatefulSet + PVC, replicas=1) | `false` |
| `governance.dbPath` | Governance SQLite DB path | `/var/lib/busbar/governance.db` |
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
