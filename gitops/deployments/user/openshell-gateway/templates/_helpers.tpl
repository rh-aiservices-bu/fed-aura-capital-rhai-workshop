{{- define "workshop.namespace" -}}
{{ .Values.namespacePrefix }}-{{ .Values.username }}
{{- end -}}
