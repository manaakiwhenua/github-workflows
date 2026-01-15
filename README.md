# GitHub Reusable Workflows

Reusable GitHub Actions workflows for building Docker images with secure GitOps deployments.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  GitHub Repo        │     │  Artifactory        │
│  (source code)      │────►│  (container images) │
│                     │     │                     │
│  • Builds images    │     └──────────┬──────────┘
│  • NO GitOps access │                │
└─────────────────────┘                │ polls for new images
                                       ▼
                        ┌─────────────────────────┐
                        │  ArgoCD Image Updater   │
                        │  (runs in cluster)      │
                        ├─────────────────────────┤
                        │  • Detects new tags     │
                        │  • Updates k8s-apps-    │
                        │    config via Git       │
                        │  • Uses ArgoCD's own    │
                        │    repo credentials     │
                        └───────────┬─────────────┘
                                    │ commits
                                    ▼
                        ┌─────────────────────────┐
                        │  k8s-apps-config        │
                        │  (GitOps repo)          │
                        └───────────┬─────────────┘
                                    │ syncs
                                    ▼
                        ┌─────────────────────────┐
                        │  ArgoCD                 │
                        │  (deploys to cluster)   │
                        └─────────────────────────┘
```

## Security Model

| Component | Access Level | Why |
|-----------|--------------|-----|
| GitHub Actions (source repos) | Artifactory only | Can't modify GitOps = can't affect prod |
| ArgoCD Image Updater | GitOps repo write | Runs in-cluster, uses existing ArgoCD credentials |
| Prod deployments | Require PR approval | Human review before production changes |

**Key benefit:** Compromising a GitHub repo's secrets cannot directly affect production workloads.

## Workflows

### docker-build.yml

Builds Docker images using `docker buildx bake`, pushes to Artifactory, and uploads build metadata.

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

**Outputs:**
- `build_id` - Build identifier (e.g., `42-abc123def`)
- `registry_prefix` - Registry path for images
- `metadata_url` - URL to build index JSON

### k8s-promote.yml (Optional)

Generates promotion information for manual PR-based deployments. Useful for prod environments.

```yaml
jobs:
  promote-prod:
    uses: manaakiwhenua/github-workflows/.github/workflows/k8s-promote.yml@main
    with:
      environment: prod
      build_id: ${{ needs.build.outputs.build_id }}
    secrets:
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}
```

## Setup

### 1. GitHub Secrets

Configure these secrets in your GitHub organization or repository:

| Secret | Description |
|--------|-------------|
| `ARTIFACTORY_HOST` | Artifactory hostname (e.g., `artifactory.landcareresearch.co.nz`) |
| `ARTIFACTORY_USERNAME` | Artifactory username |
| `ARTIFACTORY_TOKEN` | Artifactory identity token |

**Note:** No GitOps credentials needed! Image Updater handles deployment.

### 2. Bake File

Add a `docker-bake.hcl` to your repository:

```hcl
variable "REGISTRY_PREFIX" {}
variable "IMAGE_TAG" {}

target "default" {
  targets = ["app"]
}

target "app" {
  context    = "."
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY_PREFIX}/app:${IMAGE_TAG}"]
}
```

### 3. ArgoCD Image Updater

Deploy ArgoCD Image Updater to your cluster (see `k8s-apps-config/clusters/tak-k8s-nonprod/applications/argocd-image-updater/`).

### 4. Application Annotations

Add Image Updater annotations to your ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-my-app
  annotations:
    argocd-image-updater.argoproj.io/image-list: |
      app=artifactory.landcareresearch.co.nz/docker/mwlr-private/my-app/app
    argocd-image-updater.argoproj.io/app.update-strategy: newest-build
    argocd-image-updater.argoproj.io/app.allow-tags: "regexp:^[0-9]+-[a-f0-9]+$"
    argocd-image-updater.argoproj.io/write-back-method: git
```

## Deployment Flow

### Dev (Automatic)
1. Push to main → GitHub Actions builds & pushes images
2. Image Updater detects new image (polls every 2 min)
3. Image Updater commits to k8s-apps-config
4. ArgoCD syncs changes to cluster

### Prod (Manual PR)
1. Push to main → GitHub Actions builds & pushes images
2. Developer creates PR to k8s-apps-config with new image
3. Team reviews and approves PR
4. Merge → ArgoCD syncs to production

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
      push: ${{ github.event_name != 'pull_request' }}
    secrets:
      ARTIFACTORY_HOST: ${{ secrets.ARTIFACTORY_HOST }}
      ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }}
      ARTIFACTORY_TOKEN: ${{ secrets.ARTIFACTORY_TOKEN }}

  summary:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "## Build Complete" >> $GITHUB_STEP_SUMMARY
          echo "Build ID: \`${{ needs.build.outputs.build_id }}\`" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "Dev deployment: Automatic via Image Updater" >> $GITHUB_STEP_SUMMARY
```

## Manifest Path Convention

Image Updater expects manifests at:
```
clusters/{cluster}/applications/{app-name}/{environment}/{component}/deployment.yaml
```

Example:
```
clusters/tak-k8s-nonprod/applications/barcode-data-portal-mwlr/dev/fastapi-app/deployment.yaml
```
