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
{{ fail "\n\nadminTLS.enabled provides a server cert but no client CA, and busbar's admin boot-guard requires mTLS (client_ca_file) on a network-exposed admin listener — a server cert alone is not enough.\n\nFix one of:\n  --set adminTLS.certManager.enabled=true   (cert-manager wires the issuing CA as the client CA automatically)\n  --set adminTLS.clientCASecret=<secret>    (a Secret with ca.crt that admin clients must chain to)\n  --set adminInsecure=true                  (skip mTLS; token-only admin plane)\n" }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Governance boot-guard: busbar refuses to boot with governance enabled but no
admin_token. The chart renders `admin_token: ${<adminTokenEnv>}`, so that env
var must be supplied. When the chart renders the Secret (secrets.create) we can
check it here and fail fast; with an existingSecret we can't introspect, so we
trust the operator.
*/}}
{{- define "busbar.validateGovernance" -}}
{{- if .Values.governance.enabled -}}
{{- if not .Values.secrets.existingSecret -}}
{{- if not (hasKey (default dict .Values.secrets.data) .Values.governance.adminTokenEnv) -}}
{{ fail (printf "\n\ngovernance.enabled=true requires an admin token, but secrets.data has no %q key — busbar refuses to boot without governance.admin_token.\n\nFix: add the token to the Secret, e.g.\n  --set secrets.data.%s=<a-long-random-token>\nor set governance.adminTokenEnv to a key you already provide (or use an existingSecret that contains it).\n" .Values.governance.adminTokenEnv .Values.governance.adminTokenEnv) }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
