{{- define "ai-provider-adapter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ai-provider-adapter.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "ai-provider-adapter.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ai-provider-adapter.labels" -}}
app.kubernetes.io/name: {{ include "ai-provider-adapter.name" . }}
app.kubernetes.io/instance: {{ include "ai-provider-adapter.instance" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "ai-provider-adapter.instance" -}}
{{- default .Release.Name .Values.instanceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ai-provider-adapter.secretName" -}}
{{- if .Values.secret.name -}}
{{- .Values.secret.name -}}
{{- else -}}
{{- printf "%s-secret" (include "ai-provider-adapter.fullname" .) -}}
{{- end -}}
{{- end -}}
