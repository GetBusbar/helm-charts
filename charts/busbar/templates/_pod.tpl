{{/*
The shared pod spec used by both the Deployment (stateless) and the
StatefulSet (governance). Governance adds a governance-data volumeMount which
is backed by a volumeClaimTemplate in the StatefulSet, so mounting it here is
correct for both when the "governance-data" volume/claim exists.
*/}}
{{- define "busbar.podSpec" -}}
{{- $configMapName := .Values.existingConfigMap | default (include "busbar.fullname" .) -}}
{{- $secretName := .Values.secrets.existingSecret | default (include "busbar.fullname" .) -}}
metadata:
  labels:
    {{- include "busbar.selectorLabels" . | nindent 4 }}
  annotations:
    {{- if .Values.reloadOnConfigChange }}
    {{- if not .Values.existingConfigMap }}
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    {{- end }}
    {{- if and .Values.secrets.create (not .Values.secrets.existingSecret) }}
    checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
    {{- end }}
    {{- end }}
    {{- with .Values.podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "busbar.serviceAccountName" . }}
  automountServiceAccountToken: false
  securityContext:
    {{- toYaml .Values.podSecurityContext | nindent 4 }}
  containers:
    - name: busbar
      image: {{ include "busbar.image" . | quote }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      args: []
      env:
        - name: BUSBAR_CONFIG
          value: /etc/busbar/config.yaml
        {{- if or .Values.providersCatalog .Values.existingConfigMap }}
        - name: BUSBAR_PROVIDERS
          value: /etc/busbar/providers.yaml
        {{- end }}
      {{- if or (and .Values.secrets.create .Values.secrets.data) .Values.secrets.existingSecret }}
      envFrom:
        - secretRef:
            name: {{ $secretName }}
      {{- end }}
      ports:
        - name: data
          containerPort: 8080
          protocol: TCP
        {{- if .Values.service.admin.enabled }}
        - name: admin
          containerPort: 8081
          protocol: TCP
        {{- end }}
      livenessProbe:
        httpGet:
          path: /healthz
          port: data
          {{- if .Values.dataTLS.enabled }}
          scheme: HTTPS
          {{- end }}
        initialDelaySeconds: 5
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /healthz
          port: data
          {{- if .Values.dataTLS.enabled }}
          scheme: HTTPS
          {{- end }}
        initialDelaySeconds: 3
        periodSeconds: 10
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      volumeMounts:
        # Mount config.yaml (and providers.yaml only when overridden) as individual
        # files via subPath, NOT the whole /etc/busbar dir — a directory mount would
        # shadow the provider catalog baked into the image at /etc/busbar/providers.yaml.
        - name: config
          mountPath: /etc/busbar/config.yaml
          subPath: config.yaml
          readOnly: true
        {{- if .Values.providersCatalog }}
        - name: config
          mountPath: /etc/busbar/providers.yaml
          subPath: providers.yaml
          readOnly: true
        {{- end }}
        - name: tmp
          mountPath: /tmp
        {{- if .Values.adminTLS.enabled }}
        - name: admin-tls
          mountPath: /etc/busbar/tls/admin
          readOnly: true
        {{- if .Values.adminTLS.clientCASecret }}
        - name: admin-ca
          mountPath: /etc/busbar/tls/admin-ca
          readOnly: true
        {{- end }}
        {{- end }}
        {{- if .Values.dataTLS.enabled }}
        - name: data-tls
          mountPath: /etc/busbar/tls/data
          readOnly: true
        {{- end }}
        {{- if .Values.governance.enabled }}
        - name: governance-data
          mountPath: {{ dir .Values.governance.dbPath }}
        {{- end }}
  volumes:
    - name: config
      configMap:
        name: {{ $configMapName }}
    - name: tmp
      emptyDir: {}
    {{- if .Values.adminTLS.enabled }}
    - name: admin-tls
      secret:
        secretName: {{ if .Values.adminTLS.certManager.enabled }}{{ include "busbar.fullname" . }}-admin-tls{{ else }}{{ .Values.adminTLS.existingSecret }}{{ end }}
    {{- if .Values.adminTLS.clientCASecret }}
    - name: admin-ca
      secret:
        secretName: {{ .Values.adminTLS.clientCASecret }}
    {{- end }}
    {{- end }}
    {{- if .Values.dataTLS.enabled }}
    - name: data-tls
      secret:
        secretName: {{ .Values.dataTLS.existingSecret }}
    {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
