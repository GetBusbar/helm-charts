# Changelog

## 0.1.0

Initial release of the busbar Helm chart.

- Deployment (stateless) or StatefulSet + PVC (governance / single-writer SQLite).
- The two Services busbar needs: public data plane (`:8080`) and a separate,
  loopback-by-default admin plane (`:8081`) with a render-time boot-guard.
- ConfigMap + `${VAR}`-injected Secret, cert-manager admin mTLS, NetworkPolicy,
  HPA (data only), PDB, Ingress. Hardened pod securityContext.
