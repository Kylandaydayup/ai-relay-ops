{{- define "edreamcrowd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "edreamcrowd.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "edreamcrowd.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "edreamcrowd.labels" -}}
app.kubernetes.io/name: {{ include "edreamcrowd.name" . }}
app.kubernetes.io/instance: {{ include "edreamcrowd.instance" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "edreamcrowd.instance" -}}
{{- default .Release.Name .Values.instanceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "edreamcrowd.backendSecretName" -}}
{{- if .Values.backend.secret.name -}}
{{- .Values.backend.secret.name -}}
{{- else -}}
{{- printf "%s-backend-secret" (include "edreamcrowd.fullname" .) -}}
{{- end -}}
{{- end -}}
