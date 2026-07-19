# busbar Helm charts

The official Helm chart repository for [busbar](https://getbusbar.com), a Rust LLM gateway.

## Usage

```console
helm repo add busbar https://getbusbar.github.io/helm-charts
helm repo update
helm install my-busbar busbar/busbar
```

See the [chart README](charts/busbar/README.md) for the full values reference and examples.

## The two-listener model

busbar always runs **two separate listeners**:

- **Data plane** (`0.0.0.0:8080`) — public LLM proxy traffic. Fronted by a `ClusterIP` Service and,
  optionally, an Ingress.
- **Admin plane** (`admin_listen`, default loopback `127.0.0.1:8081`) — the runtime admin API.

busbar enforces a **boot-guard**: a non-loopback `admin_listen` *refuses to boot* unless the admin
listener requires **mTLS** (`admin_tls` with a `client_ca_file`) **or** an explicit `admin_insecure:
true` waiver is set.

The chart is secure by default: the admin plane stays on loopback and is **not** exposed, so
`helm install my-busbar busbar/busbar` always boots. To expose the admin plane (`service.admin.enabled=true`)
you must also enable `adminTLS.enabled=true` (mTLS, ideally via cert-manager) or `adminInsecure=true`,
or the chart fails the render with a clear message.

## Governance

With `governance.enabled=true`, busbar owns a single-writer SQLite DB, so the chart deploys a
**StatefulSet with a PVC and `replicas: 1`**. Horizontal scale of a shared SQLite governance store is
not supported. Stateless (no-governance) deployments use a Deployment and support the HPA.

## Contributing

Charts live under `charts/`. Pull requests are linted and smoke-tested with
[chart-testing](https://github.com/helm/chart-testing) against a [kind](https://kind.sigs.k8s.io)
cluster. On merge to `main`, [chart-releaser](https://github.com/helm/chart-releaser) packages the
chart and publishes it to the `gh-pages` branch / GitHub Pages.

## License

[Apache-2.0](LICENSE) © Busbar, Inc.
