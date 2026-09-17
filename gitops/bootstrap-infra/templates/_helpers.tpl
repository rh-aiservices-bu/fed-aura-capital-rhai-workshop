{{/*
Repo path for a deployment chart, honouring bootstrap.pathPrefix so this tree can
live at gitops/ (fed-aura-capital) or automation/gitops/ (rhai-features-workshop).
Usage: {{ include "bootstrap.path" (dict "ctx" . "chart" "admin/mcp") }}
*/}}
{{- define "bootstrap.path" -}}
{{- $prefix := trimSuffix "/" .ctx.Values.bootstrap.pathPrefix -}}
{{- if $prefix -}}{{ $prefix }}/deployments/{{ .chart }}{{- else -}}deployments/{{ .chart }}{{- end -}}
{{- end -}}
