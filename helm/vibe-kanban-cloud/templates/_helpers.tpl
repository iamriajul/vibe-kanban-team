{{/*
Expand the name of the chart.
*/}}
{{- define "vibe-kanban-cloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vibe-kanban-cloud.fullname" -}}
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
{{- define "vibe-kanban-cloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vibe-kanban-cloud.labels" -}}
helm.sh/chart: {{ include "vibe-kanban-cloud.chart" . }}
{{ include "vibe-kanban-cloud.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vibe-kanban-cloud.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vibe-kanban-cloud.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vibe-kanban-cloud.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vibe-kanban-cloud.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ElectricSQL fullname
*/}}
{{- define "vibe-kanban-cloud.electric.fullname" -}}
{{- printf "%s-electric" (include "vibe-kanban-cloud.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Relay fullname
*/}}
{{- define "vibe-kanban-cloud.relay.fullname" -}}
{{- printf "%s-relay" (include "vibe-kanban-cloud.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Frontend fullname
*/}}
{{- define "vibe-kanban-cloud.frontend.fullname" -}}
{{- printf "%s-frontend" (include "vibe-kanban-cloud.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
