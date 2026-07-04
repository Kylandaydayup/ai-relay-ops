{{- define "newapi-compat-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "newapi-compat-gateway.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "newapi-compat-gateway.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "newapi-compat-gateway.labels" -}}
app.kubernetes.io/name: {{ include "newapi-compat-gateway.name" . }}
app.kubernetes.io/instance: {{ include "newapi-compat-gateway.instance" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "newapi-compat-gateway.instance" -}}
{{- default .Release.Name .Values.instanceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
