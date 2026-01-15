# GitHub Reusable Workflows

Reusable GitHub Actions workflows for building Docker images and deploying to Kubernetes via GitOps.

These workflows are the GitHub Actions equivalent of:
- `docker-build-pipe` - Docker buildx bake with metadata upload
- `k8s-deploy-pipe` - GitOps image update to k8s-apps-config

## Workflows

### docker-build.yml

Builds Docker images using `docker buildx bake`, pushes to Artifactory, and uploads build metadata.

**Features:**
- Multi-target bake file support
- SBOM and provenance attestations
- Registry caching
- Build metadata JSON uploaded to Artifactory

**Usage:**
```yaml
jobs:
  build:
    uses: manaakiwhenua/github-workflows/.github/workflows/docker-build.yml@main
    with:
      bake_file: docker-bake.hcl
      bake_target: default
    secrets:
      ARTIFACTORY_HOST: ${{ secrets.ARTIFACTORY_HOST }}
      ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }}
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}
```

### k8s-deploy.yml

Updates image references in k8s-apps-config GitOps repository.

**Features:**
- Fetches build metadata from Artifactory
- Updates deployment manifests with image digest
- Commits to GitOps repo for ArgoCD sync
- Environment-based deployment gates

**Usage:**
```yaml
jobs:
  deploy:
    needs: build
    uses: manaakiwhenua/github-workflows/.github/workflows/k8s-deploy.yml@main
    with:
      environment: dev
      build_id: ${{ needs.build.outputs.build_id }}
    secrets:
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}
      GITOPS_SSH_KEY: ${{ secrets.GITOPS_SSH_KEY }}
```

## Setup Requirements

### Secrets

Configure these secrets in your GitHub organization or repository:

| Secret | Description |
|--------|-------------|
| `ARTIFACTORY_HOST` | Artifactory hostname (e.g., `artifactory.landcareresearch.co.nz`) |
| `ARTIFACTORY_USERNAME` | Artifactory username |
| `ARTIFACTORY_TOKEN` | Artifactory identity token |
| `GITOPS_SSH_KEY` | SSH deploy key with write access to k8s-apps-config |

### GitOps SSH Key Setup

1. Generate a deploy key:
   ```bash
   ssh-keygen -t ed25519 -C "github-actions-deploy" -f github-deploy-key
   ```

2. Add the **public key** to k8s-apps-config as a deploy key with write access

3. Add the **private key** as `GITOPS_SSH_KEY` secret in your source repos

### Bake File Convention

Your repository should have a `docker-bake.hcl` that uses these variables:

```hcl
variable "REGISTRY_PREFIX" {}
variable "IMAGE_TAG" {}

target "default" {
  # your targets
}

target "my-app" {
  context    = "."
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY_PREFIX}/my-app:${IMAGE_TAG}"]
}
```

## Complete Example

```yaml
# .github/workflows/ci.yml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    uses: manaakiwhenua/github-workflows/.github/workflows/docker-build.yml@main
    with:
      bake_file: docker-bake.hcl
      bake_target: default
    secrets:
      ARTIFACTORY_HOST: ${{ secrets.ARTIFACTORY_HOST }}
      ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }}
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}

  deploy-dev:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: manaakiwhenua/github-workflows/.github/workflows/k8s-deploy.yml@main
    with:
      environment: dev
      build_id: ${{ needs.build.outputs.build_id }}
    secrets:
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}
      GITOPS_SSH_KEY: ${{ secrets.GITOPS_SSH_KEY }}

  deploy-prod:
    needs: [build, deploy-dev]
    if: github.ref == 'refs/heads/main'
    uses: manaakiwhenua/github-workflows/.github/workflows/k8s-deploy.yml@main
    with:
      environment: prod
      cluster: tak-k8s-prod
      build_id: ${{ needs.build.outputs.build_id }}
    secrets:
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}
      GITOPS_SSH_KEY: ${{ secrets.GITOPS_SSH_KEY }}
```

## Manifest Path Convention

The deploy workflow expects manifests at:
```
clusters/{cluster}/applications/{app-name}/{environment}/{component}/deployment.yaml
```

Example for `barcode-data-portal-mwlr` with `fastapi-app` component:
```
clusters/tak-k8s-nonprod/applications/barcode-data-portal-mwlr/dev/fastapi-app/deployment.yaml
```
