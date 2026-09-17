{{/* Workshop namespace for the current user, e.g. wksp-user1 */}}
{{- define "workshop.namespace" -}}
{{ .Values.namespacePrefix }}-{{ .Values.username }}
{{- end -}}
