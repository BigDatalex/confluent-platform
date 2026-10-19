{{/* Usage: include "confluent-apps.syncPolicy" (dict "root" $ "extraSyncOptions" (list ...)) */}}
{{- define "confluent-apps.syncPolicy" -}}
{{- $sp := .root.Values.syncPolicy -}}
{{- with $sp.automated }}
automated:
  {{- toYaml . | nindent 2 }}
{{- end }}
syncOptions:
  - CreateNamespace=true
  {{- range .extraSyncOptions }}
  - {{ . }}
  {{- end }}
{{- with $sp.retry }}
retry:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
