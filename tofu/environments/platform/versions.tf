terraform {
  required_version = ">= 1.8.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    # kubectl_manifest applies custom resources without needing their CRDs at plan time,
    # which kubernetes_manifest does. That matters on a fresh cluster: the Argo CD and
    # Cilium CRDs are installed by the same apply that creates the objects using them.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Local state, gitignored, encrypted: it holds the generated passwords. The encryption
  # block is not in this file because it must not carry the passphrase; it is supplied
  # through the TF_ENCRYPTION environment variable (see README.md and encryption.example).
}
