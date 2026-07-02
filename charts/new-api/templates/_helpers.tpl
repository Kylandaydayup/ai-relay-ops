{{- define "new-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "new-api.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "new-api.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "new-api.labels" -}}
app.kubernetes.io/name: {{ include "new-api.name" . }}
app.kubernetes.io/instance: {{ include "new-api.instance" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "new-api.instance" -}}
{{- default .Release.Name .Values.instanceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "new-api.secretName" -}}
{{- if .Values.secret.name -}}
{{- .Values.secret.name -}}
{{- else -}}
{{- printf "%s-secret" (include "new-api.fullname" .) -}}
{{- end -}}
{{- end -}}
