# Changelog

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
