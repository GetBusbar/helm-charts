# Changelog

## 0.2.0

busbar 1.5.0 config redesign — this chart now emits 1.5.0 config syntax:

- `appVersion` bumped to `1.5.0`; a fresh `helm install` with no `image.tag` override now
  pulls `getbusbar/busbar:1.5.0`.
- `tls.cert_file`/`key_file` and `admin_tls.cert_file`/`key_file`/`client_ca_file` →
  `cert: { file }` / `key: { file }` / `client_ca: { file }` secret references (1.5.0
  removed the plaintext path fields).
- `governance.enabled` now wires `auth.admin_auth: [admin-tokens: {token: {env:
  <adminTokenEnv>}}]` instead of the removed `governance.admin_token`. **Caveat:** 1.5.0
  moved durable key/usage storage behind a signed store plugin
  (`busbar-store-sqlite`) loaded via `plugins.dir`; this chart does not yet fetch/mount
  that plugin, so `governance.enabled` currently gives you the admin token + the
  StatefulSet/PVC scaffold, but admin/key state is still in-memory (ephemeral) until
  plugin support is added. Tracked as follow-up work.
- Added `.github/workflows/bump-chart.yml`, mirroring `homebrew-busbar`'s bump-formula
  workflow: polls `GetBusbar/busbar` releases daily (+ on-demand / `repository_dispatch`)
  and auto-bumps `appVersion` + the chart `version`.

## 0.1.3

- Releases now carry a **Sigstore build-provenance attestation** on the chart `.tgz`,
  verifiable with `gh attestation verify busbar-<version>.tgz --repo GetBusbar/helm-charts`.
- Listed on [Artifact Hub](https://artifacthub.io/packages/search?repo=busbar-helm-charts).

## 0.1.2

Found by testing the admin-mTLS path on a live (cert-manager) cluster:

- **`adminTLS.enabled` now yields real mTLS.** busbar's boot-guard requires a client CA
  (`client_ca_file`) on a network-exposed admin listener, not just a server cert — a
  server-cert-only config crash-looped. The chart now wires `client_ca_file` from the
  `ca.crt` that cert-manager writes into the server-cert Secret (clients present certs
  signed by the same issuing CA), so `adminTLS.certManager.enabled=true` works out of the
  box. An explicit `clientCASecret` still takes precedence.
- **New guard:** `adminTLS.enabled` with an `existingSecret` but no `clientCASecret` (where
  the chart can't derive a CA) now fails `helm install` with guidance instead of
  crash-looping the pod.

## 0.1.1

Fixes found by deploying the chart to a live (kind) cluster — none were catchable by
`helm lint`/`helm template`:

- **Config mount no longer shadows the image's provider catalog.** The ConfigMap was
  mounted over the whole `/etc/busbar` directory, hiding the built-in
  `/etc/busbar/providers.yaml` and crash-looping the pod. Now `config.yaml` (and
  `providers.yaml` only when `providersCatalog` is set) mount as individual files via
  `subPath`.
- **Governance now wires an admin token.** busbar refuses to boot with governance
  enabled but no `admin_token`. The chart renders `governance.admin_token: ${<env>}`
  from the new `governance.adminTokenEnv` (default `BUSBAR_ADMIN_TOKEN`), and a
  render-time guard fails `helm install` fast if the token isn't provided.
- **Governance keeps a normal data Service.** The data (traffic) Service is no longer
  made headless for the StatefulSet — a separate headless Service provides stable pod
  identity. This keeps the traffic-plane cluster VIP and lets a release switch
  governance on/off without hitting Service `clusterIP` immutability.

## 0.1.0

Initial release of the busbar Helm chart.

- Deployment (stateless) or StatefulSet + PVC (governance / single-writer SQLite).
- The two Services busbar needs: public data plane (`:8080`) and a separate,
  loopback-by-default admin plane (`:8081`) with a render-time boot-guard.
- ConfigMap + `${VAR}`-injected Secret, cert-manager admin mTLS, NetworkPolicy,
  HPA (data only), PDB, Ingress. Hardened pod securityContext.
