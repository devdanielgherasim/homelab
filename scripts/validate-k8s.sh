#!/usr/bin/env bash
# Validates the Kubernetes manifests under kubernetes/ (or the paths given) with
# kubeconform, against the Kubernetes 1.37 schemas plus the schemas of the custom
# resources used here (Argo CD, Gateway API, Prometheus Operator, ...).
#
# Custom-resource schemas come from the community CRDs-catalog, pinned to a commit
# so the result does not change when the catalog does. A kind that has no schema
# there is an error, not a silent skip (-strict without -ignore-missing-schemas).
# Helm values files are not resources (no `kind`), so they are skipped, and so are
# CustomResourceDefinitions themselves (the default schema set has none; the API
# server validates a CRD when it is applied).
#
#   KUBECONFORM=./kubeconform scripts/validate-k8s.sh [path ...]
set -euo pipefail

KUBECONFORM="${KUBECONFORM:-kubeconform}"
KUBERNETES_VERSION="1.37.0" # the cluster's version (kubernetes/bootstrap/README, STATUS.md)
CRD_CATALOG_REF="ad3b08c5045129d7bb1eeffd8e61719b2c8dd1e2" # datreeio/CRDs-catalog, 2026-09-08

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

paths=("$@")
[ "${#paths[@]}" -gt 0 ] || paths=(kubernetes)

find "${paths[@]}" -name '*.yaml' -print0 | xargs -0 -r "$KUBECONFORM" \
  -strict -summary \
  -skip CustomResourceDefinition \
  -kubernetes-version "$KUBERNETES_VERSION" \
  -schema-location default \
  -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRD_CATALOG_REF}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  -ignore-filename-pattern '(^|/)values[^/]*[.]ya?ml$'
