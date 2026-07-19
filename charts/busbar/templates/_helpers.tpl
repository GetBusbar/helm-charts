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
{{- end -}}
{{- end }}
