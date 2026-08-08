{{/*
Expand the name of the chart.
*/}}
{{- define "busbar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited.
*/}}
{{- define "busbar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "busbar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "busbar.labels" -}}
helm.sh/chart: {{ include "busbar.chart" . }}
{{ include "busbar.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "busbar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "busbar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "busbar.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "busbar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The image reference, with tag falling back to appVersion.
*/}}
{{- define "busbar.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
The admin_listen bind address. Loopback by default (never exposed); when the
admin Service is enabled we bind 0.0.0.0 so it is reachable in-cluster.
*/}}
{{- define "busbar.adminListen" -}}
{{- if .Values.service.admin.enabled -}}
0.0.0.0:8081
{{- else -}}
127.0.0.1:8081
{{- end -}}
{{- end }}

{{/*
Boot-guard enforcement: a non-loopback admin_listen refuses to boot unless it
requires mTLS (adminTLS) or adminInsecure is set. Fail the render early with a
clear message so the user never ships an un-bootable deployment.
*/}}
{{- define "busbar.validateAdmin" -}}
{{- if .Values.service.admin.enabled -}}
{{- if and (not .Values.adminTLS.enabled) (not .Values.adminInsecure) -}}
{{ fail "\n\nservice.admin.enabled=true exposes the admin plane on a non-loopback address (0.0.0.0:8081), which busbar's boot-guard REFUSES TO BOOT unless the admin listener requires mTLS or an explicit insecure waiver is set.\n\nFix one of:\n  --set adminTLS.enabled=true    (recommended: mTLS via cert-manager or an existing cert + client CA)\n  --set adminInsecure=true       (insecure waiver; only in a trusted, network-policied namespace)\n\nOr leave service.admin.enabled=false (default) to keep the admin plane on loopback.\n" }}
{{- end -}}
{{- /* mTLS needs a client CA, not just a server cert. cert-manager wires the issuing CA
       automatically; with an existingSecret the operator must supply a client CA. */}}
{{- if and .Values.adminTLS.enabled (not .Values.adminTLS.certManager.enabled) (not .Values.adminTLS.clientCASecret) -}}
{{ fail "\n\nadminTLS.enabled provides a server cert but no client CA, and busbar's admin boot-guard requires mTLS (client_ca) on a network-exposed admin listener; a server cert alone is not enough.\n\nFix one of:\n  --set adminTLS.certManager.enabled=true   (cert-manager wires the issuing CA as the client CA automatically)\n  --set adminTLS.clientCASecret=<secret>    (a Secret with ca.crt that admin clients must chain to)\n  --set adminInsecure=true                  (skip mTLS; token-only admin plane)\n" }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Governance boot-guard: busbar gates the admin plane on an admin token, which the
chart wires as identity-providers.admin-tokens -> auth.admin_auth, sourcing the
token from ${<adminTokenEnv>}. That env var must therefore be supplied. When the
chart renders the Secret (secrets.create) we can check it here and fail fast;
with an existingSecret we can't introspect, so we trust the operator.

Also guards the 1.5.x store split: every durable store is a signed store plugin
and busbar 1.5.3's image ships none, so naming a non-memory store module without
wiring plugins yourself is an exit-1 config.
*/}}
{{- define "busbar.validateGovernance" -}}
{{- if .Values.governance.enabled -}}
{{- if not .Values.secrets.existingSecret -}}
{{- if not (hasKey (default dict .Values.secrets.data) .Values.governance.adminTokenEnv) -}}
{{ fail (printf "\n\ngovernance.enabled=true requires an admin token, but secrets.data has no %q key. busbar refuses to gate its admin plane without one.\n\nFix: add the token to the Secret, e.g.\n  --set secrets.data.%s=<a-long-random-token>\nor set governance.adminTokenEnv to a key you already provide (or use an existingSecret that contains it).\n" .Values.governance.adminTokenEnv .Values.governance.adminTokenEnv) }}
{{- end -}}
{{- end -}}
{{- $storeModule := .Values.governance.store.module | default "memory" -}}
{{- if ne $storeModule "memory" -}}
{{- $plugins := (default dict .Values.config).plugins | default dict -}}
{{- if not $plugins.enabled -}}
{{ fail (printf "\n\ngovernance.store.module=%q is a store PLUGIN, but config.plugins.enabled is not true, so busbar would exit 1 at boot:\n  [error] store.module: %q requires the plugin subsystem, but plugins.enabled is false (the default).\n\nEvery durable store in busbar 1.5.x is a signed store plugin, and the getbusbar/busbar:1.5.3 image ships no plugin tarballs (`busbar --list-plugins` prints \"no plugin tarballs found\"), so the chart cannot supply one for you.\n\nFix one of:\n  --set governance.store.module=memory   (ephemeral: keys, group usage and ledgers reset on restart)\n  mount the signed %q store plugin into the pod and set config.plugins.enabled=true plus config.plugins.dir to that path\n" $storeModule $storeModule $storeModule) }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Config boot-guard: busbar is a proxy in front of upstream LLM providers and
refuses to boot without a `providers` map, so an empty .Values.config renders a
two-line listener stub that exits 1 with
  [error] config.yaml: invalid YAML: missing field `providers`
There is no honest bootable zero-config default (it would mean inventing
credentials for an upstream nobody configured), so fail the render with the
config the user actually needs instead of shipping a CrashLoopBackOff.
*/}}
{{- define "busbar.validateConfig" -}}
{{- if not .Values.existingConfigMap -}}
{{- if not .Values.config -}}
{{ fail "\n\n`config` is REQUIRED and is empty.\n\nbusbar is a gateway in front of upstream LLM providers: with no `providers` map it exits 1 at boot with\n  [error] config.yaml: invalid YAML: missing field `providers`\nso there is no bootable zero-config default and the chart refuses to render one.\n\nSupply a busbar 1.5.x config, e.g. in a values file:\n\n  secrets:\n    data:\n      ANTHROPIC_KEY: sk-ant-...\n      BUSBAR_ADMIN_TOKEN: a-long-random-admin-token\n  config:\n    identity-providers:\n      admin-tokens:\n        module: admin-tokens\n        token: { env: BUSBAR_ADMIN_TOKEN }\n    auth:\n      chain: []\n      admin_auth: [admin-tokens]\n    providers:\n      anthropic:\n        api_key: { env: ANTHROPIC_KEY }\n    models:\n      claude:\n        provider: anthropic\n    pools:\n      default:\n        members:\n          - model: claude\n\nNote `auth.chain: []` is an OPEN RELAY and is for a first boot only; set a real\nauth chain before you expose the data plane.\n\nOr point the chart at a config you already manage with `existingConfigMap`.\n" }}
{{- end -}}
{{- end -}}
{{- end }}
