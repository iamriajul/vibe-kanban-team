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

{{- define "vibe-kanban-team.ingress.className" -}}
{{- $className := .className | default "" -}}
{{- if $className -}}
{{- $className -}}
{{- else -}}
{{- .root.Values.global.ingressClassName | default "" -}}
{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.ingress.annotations" -}}
{{- $annotations := dict -}}
{{- with .root.Values.global.ingress.annotations }}
{{- $annotations = mergeOverwrite $annotations . -}}
{{- end }}
{{- with .annotations }}
{{- $annotations = mergeOverwrite $annotations . -}}
{{- end }}
{{- $clusterIssuer := .root.Values.global.tls.clusterIssuer | default "" -}}
{{- if $clusterIssuer }}
{{- $_ := set $annotations "cert-manager.io/cluster-issuer" $clusterIssuer -}}
{{- end }}
{{- if $annotations }}
{{- toYaml $annotations -}}
{{- end }}
{{- end }}

{{- define "vibe-kanban-team.remote.host" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if and $domain .Values.frontend.enabled -}}
{{- printf "remote.%s" $domain -}}
{{- else -}}
{{- $domain -}}
{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.remote.publicBaseUrl" -}}
{{- $host := include "vibe-kanban-team.remote.host" . -}}
{{- if $host -}}{{ printf "https://%s" $host }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.relay.host" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ printf "relay.%s" $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.host" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.codeServer.host" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ printf "code.%s" $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.codeServer.proxyHost" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ printf "*.%s" $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.auth.host" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ printf "auth.%s" $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.cookieDomain" -}}
{{- $domain := .Values.global.domain | default "" -}}
{{- if $domain -}}{{ printf ".%s" $domain }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.proxyDomain" -}}
{{- $codeServerHost := include "vibe-kanban-team.codeServer.host" . -}}
{{- if and .Values.frontend.codeServerIngress.enabled $codeServerHost -}}{{ printf "{{port}}-%s" $codeServerHost }}{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.authAnnotations" -}}
{{- $annotations := dict -}}
{{- with .Values.frontend.auth.protectedIngressAnnotations }}
{{- $annotations = mergeOverwrite $annotations . -}}
{{- end }}
{{- $ingressClassName := .Values.global.ingressClassName | default "" -}}
{{- if and .Values.frontend.auth.enabled (contains "nginx" $ingressClassName) (include "vibe-kanban-team.auth.host" .) -}}
{{- $_ := set $annotations "nginx.ingress.kubernetes.io/auth-url" (printf "https://%s/oauth2/auth" (include "vibe-kanban-team.auth.host" .)) -}}
{{- $_ := set $annotations "nginx.ingress.kubernetes.io/auth-signin" (printf "https://%s/oauth2/start?rd=$scheme://$host$request_uri" (include "vibe-kanban-team.auth.host" .)) -}}
{{- $_ := set $annotations "nginx.ingress.kubernetes.io/auth-response-headers" "X-Auth-Request-User,X-Auth-Request-Email,Authorization" -}}
{{- else if and .Values.frontend.auth.enabled .Values.frontend.auth.createTraefikMiddleware (contains "traefik" $ingressClassName) -}}
{{- $_ := set $annotations "traefik.ingress.kubernetes.io/router.middlewares" (printf "%s-%s-oauth2-proxy@kubernetescrd" .Release.Namespace (include "vibe-kanban-team.frontend.fullname" .)) -}}
{{- end }}
{{- if $annotations }}
{{- toYaml $annotations -}}
{{- end }}
{{- end }}

{{- define "vibe-kanban-team.remote.ingressEnabled" -}}
{{- if or .Values.ingress.enabled (ne (include "vibe-kanban-team.remote.host" .) "") -}}true{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.relay.ingressEnabled" -}}
{{- if and .Values.relay.enabled (or .Values.relay.ingress.enabled (ne (include "vibe-kanban-team.relay.host" .) "")) -}}true{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.ingressEnabled" -}}
{{- if and .Values.frontend.enabled (or .Values.frontend.ingress.enabled (ne (include "vibe-kanban-team.frontend.host" .) "")) -}}true{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.codeServerIngressEnabled" -}}
{{- if and .Values.frontend.enabled .Values.frontend.codeServerIngress.enabled -}}true{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.frontend.authIngressEnabled" -}}
{{- if and .Values.frontend.enabled .Values.frontend.auth.enabled (or (ne (.Values.frontend.auth.host | default "") "") (ne (include "vibe-kanban-team.auth.host" .) "")) -}}true{{- end -}}
{{- end }}

{{- define "vibe-kanban-team.remote.structuredEnv" -}}
{{- $database := .Values.config.existingSecrets.database -}}
{{- $app := .Values.config.existingSecrets.app -}}
{{- $oauth := .Values.config.existingSecrets.oauth -}}
{{- if $database.name }}
- name: SERVER_DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $database.name }}
      key: {{ $database.urlKey }}
{{- end }}
{{- if $app.name }}
- name: VIBEKANBAN_REMOTE_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $app.name }}
      key: {{ $app.jwtSecretKey }}
- name: ELECTRIC_ROLE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $app.name }}
      key: {{ $app.electricRolePasswordKey }}
{{- end }}
{{- if $oauth.name }}
- name: GITHUB_OAUTH_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $oauth.name }}
      key: {{ $oauth.githubClientIdKey }}
- name: GITHUB_OAUTH_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $oauth.name }}
      key: {{ $oauth.githubClientSecretKey }}
{{- end }}
{{- end }}

{{- define "vibe-kanban-team.relay.structuredEnv" -}}
{{- $database := .Values.config.existingSecrets.database -}}
{{- $app := .Values.config.existingSecrets.app -}}
{{- if $database.name }}
- name: SERVER_DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $database.name }}
      key: {{ $database.urlKey }}
{{- end }}
{{- if $app.name }}
- name: VIBEKANBAN_REMOTE_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $app.name }}
      key: {{ $app.jwtSecretKey }}
{{- end }}
{{- end }}

{{- define "vibe-kanban-team.electric.structuredEnv" -}}
{{- $database := .Values.config.existingSecrets.database -}}
{{- if $database.name }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $database.name }}
      key: {{ $database.electricUrlKey }}
{{- end }}
{{- end }}
