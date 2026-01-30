{{/*
Expand the name of the chart.
*/}}
{{- define "frontend-api.name" -}}
{{- default .Chart.Name .Values.frontendApi.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "frontend-api.fullname" -}}
{{- if .Values.frontendApi.fullnameOverride }}
{{- .Values.frontendApi.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.frontendApi.nameOverride }}
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
{{- define "frontend-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "frontend-api.labels" -}}
helm.sh/chart: {{ include "frontend-api.chart" . }}
{{ include "frontend-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "frontend-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
