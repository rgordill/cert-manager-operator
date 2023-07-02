#!/bin/sh
set -eu

if ! command -v jb &> /dev/null; then
  echo "jb could not be found. See https://github.com/jsonnet-bundler/jsonnet-bundler"
  exit 1
fi

# Generate jsonnet mixin prometheusrule and dashboards manifest.

cd jsonnet && jb update
jsonnet -J vendor main.jsonnet  | gojsontoyaml > ../manifests/0000_90_cert-manager-operator_01_prometheusrule.yaml
jsonnet -J vendor dashboard.jsonnet  | gojsontoyaml > ../manifests/0000_90_cert-manager-operator_02-dashboards.yaml