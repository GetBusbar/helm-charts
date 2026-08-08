# Changelog

## 0.2.8

Chart 0.2.7 / appVersion 1.5.3 could not boot by any documented route. Three defects, all
reproduced by running `getbusbar/busbar:1.5.3` with the chart's own rendered config mounted
read-only at the chart's mount path as the chart's uid (65532), plus a fourth found on the way.

- **The chart now manages `config.locked` / `config.overlay` (`configMutability`).** busbar 1.5.3
  refuses to boot a mutable config (`config.locked: false`, its default) whose overlay backend is
  not writable, and that backend defaults to `busbar-overlay.json` next to the resolved
  `config.yaml`, i.e. `/etc/busbar/busbar-overlay.json` - a read-only ConfigMap subPath mount under
  `readOnlyRootFilesystem: true`. Every install, including a correct one, died with
  `[error] config is mutable (config.locked: false) but the overlay backend ... is not writable`.
  New `configMutability.mode` defaults to **`locked`**: a Helm release is a GitOps deployment, the
  ConfigMap is the source of truth, and locked is the only mode that behaves correctly at
  `replicaCount > 1`. `mode: overlay` re-enables admin-API config mutation against the chart's
  writable `/tmp` emptyDir, with the ephemerality and replica-divergence tradeoff spelled out in
  `values.yaml` and the README. `mode: none` hands the keys back to you. `.Values.config.config`
  always wins over the chart's value.
- **`config` is now required, and an empty one fails the render.** `helm install my-busbar
  busbar/busbar` with no values rendered a two-line listener stub that busbar rejects with
  `[error] config.yaml: invalid YAML: missing field 'providers'`, while both READMEs claimed the
  defaults "always boot". There is no honest bootable zero-config default for a gateway that
  proxies upstream providers, so the chart fails fast with the minimal 1.5.x config inline in the
  error, and both READMEs were corrected.
- **Every config example is now busbar 1.5.x syntax.** The chart README's "Minimal" example was a
  1.x config that 1.5.3 hard-rejects (`auth.client_tokens:`, `providers.openai.api_key_env:`).
  Both READMEs, the `values.yaml` comments and all `ci/` fixtures now use secret references
  (`api_key: { env: VAR }`), an `identity-providers` admin-tokens definition referenced by name
  from `auth.admin_auth`, and pool members keyed on `model:` rather than the retired `target:`.
- **`governance.enabled=true` no longer renders a config busbar refuses to boot.** It emitted a
  top-level `governance:` block, which 1.5.3 flags as a 1.x marker
  (`governance: block (dissolved into store / rate_card / per_request_fee / groups / advanced /
  auth)`). It now renders `identity-providers.admin-tokens` + `auth.admin_auth: [admin-tokens]` +
  `store:`. New `governance.store.module` defaults to `memory` because every durable store in
  1.5.x is a signed store plugin and the 1.5.3 image ships none; naming another module without
  wiring `config.plugins` fails the render with the exact error busbar would have printed.
- **`adminTLS`/`dataTLS` now emit 1.5.x secret references.** Caught by `ct install` on a real kind
  cluster: the chart still rendered the 1.4.x plaintext path fields, so every TLS-enabled install
  died with `[error] config.yaml: invalid YAML: admin_tls: unknown field 'cert_file', expected one
  of 'cert', 'key', 'client_ca'`. `cert_file`/`key_file`/`client_ca_file` are now
  `cert: { file: ... }` / `key: { file: ... }` / `client_ca: { file: ... }`.
- Added `ci/overlay-values.yaml` so `configMutability.mode=overlay` is covered by `ct install`.
- The bundled `helm test` now retries. It could fire before the data Service endpoint had
  propagated and fail instantly with `curl: (7) ... Could not connect to server`, reporting a
  healthy gateway as broken.

`appVersion` stays at `1.5.3`.

## 0.2.3

Fixes an Artifact Hub scan failure (`image not found (package busbar:0.2.2)`) and a real
ImagePullBackOff for anyone installing the chart with defaults: `appVersion`/the default image
tag pointed at `1.5.0`, which has never been tagged or published — `getbusbar/busbar:1.5.0` does
not exist on Docker Hub.

- **Reverts the `1.5.0` look-ahead bump from 0.2.0/0.2.2.** `appVersion` (and the default
  `image.tag`) go back to **`1.4.1`**, the real latest published release (verified against
  Docker Hub: `getbusbar/busbar:1.4.1` resolves and matches `:latest`).
- **Reverts the config-syntax rewrite from 0.2.0** (`configmap.yaml`, `_helpers.tpl`, the `ci/`
  value fixtures, `values.yaml`/`README.md` wording) back to the syntax the real `1.4.1` binary
  actually understands: `api_key_env`, `tls`/`admin_tls` `*_file` plaintext fields, and
  `governance.admin_token`. The `1.5.0` secret-reference syntax (`api_key: { env }`, `cert: {
  file }`, `auth.admin_auth`) does not exist in any published busbar release yet (confirmed
  against the `1.4.1` source) — shipping it as the chart default would have swapped an
  ImagePullBackOff for a config-parse boot failure instead of fixing anything.
- The `bump-chart` workflow's "never move `appVersion` backward" guard (added in 0.2.2) is
  unchanged and is still correct in general — the bug was a *manual* look-ahead bump to an
  unreleased version, not the automation. Going forward, don't hand-bump `appVersion`/the image
  annotation ahead of a tag that's actually published and pullable; let `bump-chart` track real
  releases.

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
