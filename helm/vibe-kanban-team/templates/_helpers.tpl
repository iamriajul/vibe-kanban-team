{{/*
Expand the name of the chart.
*/}}
{{- define "vibe-kanban-team.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vibe-kanban-team.fullname" -}}
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
{{- define "vibe-kanban-team.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vibe-kanban-team.labels" -}}
helm.sh/chart: {{ include "vibe-kanban-team.chart" . }}
{{ include "vibe-kanban-team.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vibe-kanban-team.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vibe-kanban-team.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vibe-kanban-team.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vibe-kanban-team.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ElectricSQL fullname
*/}}
{{- define "vibe-kanban-team.electric.fullname" -}}
{{- printf "%s-electric" (include "vibe-kanban-team.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Relay fullname
*/}}
{{- define "vibe-kanban-team.relay.fullname" -}}
{{- printf "%s-relay" (include "vibe-kanban-team.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Frontend fullname
*/}}
{{- define "vibe-kanban-team.frontend.fullname" -}}
{{- printf "%s-frontend" (include "vibe-kanban-team.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
