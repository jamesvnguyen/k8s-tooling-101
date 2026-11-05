{{/*
Named templates. Files starting with _ are not rendered as manifests.
Prefix every name with the chart name: template names are global.
*/}}

{{/* Name for every object: <release>-<chart>, max 63 characters */}}
{{- define "nginx.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Labels that identify the pods. Used in selectors, so never change them after install. */}}
{{- define "nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Every label: the selector labels plus informational ones */}}
{{- define "nginx.labels" -}}
{{ include "nginx.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
environment: {{ .Values.environment }}
{{- end }}
