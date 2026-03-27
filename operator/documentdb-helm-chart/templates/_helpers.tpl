{{- define "documentdb-chart.name" -}}
documentdb-operator
{{- end -}}

{{/*
Render a deployment image. Allow an explicit tag override to win so callers can
switch to local/test tags without clearing the default release ref first.
Otherwise prefer the explicit ref/digest and finally fall back to
repository + tag/defaultTag for compatibility with older values files.
*/}}
{{- define "documentdb-chart.renderImage" -}}
{{- $ref := default "" .ref -}}
{{- $digest := default "" .digest -}}
{{- $repository := default "" .repository -}}
{{- $tag := default "" .tag -}}
{{- $defaultTag := default "" .defaultTag -}}
{{- if and $repository $tag -}}
  {{- if $digest -}}
    {{- printf "%s:%s@%s" $repository $tag $digest -}}
  {{- else -}}
    {{- printf "%s:%s" $repository $tag -}}
  {{- end -}}
{{- else if $ref -}}
  {{- if $digest -}}
    {{- printf "%s@%s" $ref $digest -}}
  {{- else -}}
    {{- $ref -}}
  {{- end -}}
{{- else if $repository -}}
  {{- $resolvedTag := default $defaultTag $tag -}}
  {{- if $resolvedTag -}}
    {{- if $digest -}}
      {{- printf "%s:%s@%s" $repository $resolvedTag $digest -}}
    {{- else -}}
      {{- printf "%s:%s" $repository $resolvedTag -}}
    {{- end -}}
  {{- else -}}
    {{- if $digest -}}
      {{- printf "%s@%s" $repository $digest -}}
    {{- else -}}
      {{- $repository -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Render default runtime image refs passed into the operator. Prefer explicit refs,
and fall back to documentDbVersion-derived tags during the compatibility window.
*/}}
{{- define "documentdb-chart.runtimeDefaultImage" -}}
{{- $ref := default "" .ref -}}
{{- $digest := default "" .digest -}}
{{- $repository := default "" .repository -}}
{{- $legacyVersion := default "" .legacyVersion -}}
{{- if $ref -}}
  {{- if $digest -}}
    {{- printf "%s@%s" $ref $digest -}}
  {{- else -}}
    {{- $ref -}}
  {{- end -}}
{{- else if and $repository $legacyVersion -}}
  {{- printf "%s:%s" $repository $legacyVersion -}}
{{- end -}}
{{- end -}}
