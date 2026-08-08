# busbar Helm charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/busbar-helm-charts)](https://artifacthub.io/packages/search?repo=busbar-helm-charts)

The official Helm chart repository for [busbar](https://getbusbar.com), a Rust LLM gateway.

## Usage

```console
helm repo add busbar https://getbusbar.github.io/helm-charts
helm repo update
helm install my-busbar busbar/busbar -f my-values.yaml
```

`config` is **required** and has no default. busbar is a gateway in front of upstream LLM
providers, so there is no meaningful zero-config install: with no `providers` map the binary
exits 1 at boot. `helm install` with no `config` therefore **fails the render** and prints the
minimal config you need, rather than handing you a `CrashLoopBackOff`.

See the [chart README](charts/busbar/README.md) for the full values reference and examples.

## The two-listener model

busbar always runs **two separate listeners**:

- **Data plane** (`0.0.0.0:8080`) — public LLM proxy traffic. Fronted by a `ClusterIP` Service and,
  optionally, an Ingress.
- **Admin plane** (`admin_listen`, default loopback `127.0.0.1:8081`) — the runtime admin API.

busbar enforces a **boot-guard**: a non-loopback `admin_listen` *refuses to boot* unless the admin
listener requires **mTLS** (`admin_tls` with a `client_ca`) **or** an explicit `admin_insecure:
true` waiver is set.

The chart is secure by default: the admin plane stays on loopback and is **not** exposed, so the
admin boot-guard is always satisfied. To expose the admin plane (`service.admin.enabled=true`)
you must also enable `adminTLS.enabled=true` (mTLS, ideally via cert-manager) or `adminInsecure=true`,
or the chart fails the render with a clear message.

## Config mutability

busbar 1.5.3 refuses to boot a *mutable* config (`config.locked: false`, its default) whose overlay
backend is not writable, and that backend defaults to `busbar-overlay.json` next to the resolved
`config.yaml`. This chart mounts `config.yaml` from a read-only ConfigMap under
`readOnlyRootFilesystem`, so the chart manages that setting for you: `configMutability.mode`
defaults to `locked` (a Helm release is a GitOps deployment; you change config with
`helm upgrade`). Set `configMutability.mode=overlay` to re-enable admin-API config mutation, and
read the tradeoff in `values.yaml` first: the default overlay path is pod-local and ephemeral.

## Governance

With `governance.enabled=true`, busbar owns single-writer state, so the chart deploys a
**StatefulSet with a PVC and `replicas: 1`**. Horizontal scale of a shared single-writer store is
not supported. Stateless (no-governance) deployments use a Deployment and support the HPA.

busbar 1.5.x moved every durable store behind a signed **store** plugin, and the
`getbusbar/busbar:1.5.3` image ships no plugin tarballs, so `governance.store.module` defaults to
`memory` (ephemeral). Naming any other module without also wiring `config.plugins` fails the render.

## Contributing

Charts live under `charts/`. Pull requests are linted and smoke-tested with
[chart-testing](https://github.com/helm/chart-testing) against a [kind](https://kind.sigs.k8s.io)
cluster. On merge to `main`, [chart-releaser](https://github.com/helm/chart-releaser) packages the
chart and publishes it to the `gh-pages` branch / GitHub Pages.

## License

[Apache-2.0](LICENSE) © Busbar, Inc.
