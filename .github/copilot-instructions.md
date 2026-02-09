# Copilot Instructions for github-workflows

## Repository Overview

This repository contains reusable GitHub Actions workflows and composite actions for the organisation. It provides:
- Docker build workflow (docker-build.yml) - equivalent to docker-build-pipe for Bitbucket
- K8s deploy action - triggers k8s-apps-config Bitbucket pipelines for GitOps deployments

## Directory Structure

```
.github/
  workflows/
    docker-build.yml     # Reusable workflow for Docker builds
actions/
  k8s-deploy/           # Composite action to trigger K8s deployments
examples/
  consumer-workflow.yml # Example of how to use the workflows
```

## Related Repositories

- **k8s-apps-config**: Kubernetes manifests deployed via ArgoCD (Bitbucket)
- **docker-build-pipe**: Original Bitbucket Pipes implementation this is based on

## Lessons Learned

Document any issues that took multiple attempts to resolve here for future reference:

- **Bitbucket Pipeline UUID encoding**: Bitbucket API returns pipeline UUIDs wrapped in curly braces like `{uuid}`. When using these in subsequent API calls (e.g., to poll pipeline status), the braces must be URL-encoded (`%7B` and `%7D`), otherwise the API returns no data (null state).

- **BuildKit CA certificates**: When using `docker-container` driver with BuildKit, the container is isolated from the host's certificate store. To add custom CA certs:
  1. Install CA on host (for docker login): `/usr/local/share/ca-certificates/` + `update-ca-certificates`
  2. Add to Docker daemon certs: `/etc/docker/certs.d/${REGISTRY_HOST}/ca.crt`
  3. Restart Docker daemon: `sudo systemctl restart docker`
  4. Inject into BuildKit container after it starts:
     ```bash
     docker cp /tmp/ca.crt "${BUILDKIT_CONTAINER}:/tmp/ca.crt"
     docker exec "$BUILDKIT_CONTAINER" sh -c 'cat /tmp/ca.crt >> /etc/ssl/certs/ca-certificates.crt'
     docker restart "$BUILDKIT_CONTAINER"
     ```
  Note: BuildKit uses Alpine Linux, so certs are at `/etc/ssl/certs/ca-certificates.crt`, not `/usr/local/share/ca-certificates/`.

- **docker-bake.hcl tag format**: When using docker-build-pipe, the `REGISTRY_PREFIX` variable already includes the full path up to and including the repo slug (e.g., `artifactory.../docker/mwlr-private/platform-docs`). Do NOT add the repo name again in the tag. For single-target builds, use `tags = ["${REGISTRY_PREFIX}:${IMAGE_TAG}"]` not `tags = ["${REGISTRY_PREFIX}/myapp:${IMAGE_TAG}"]`. Adding the repo name creates a double path like `/platform-docs/platform-docs` which won't match deployment manifests.

- **Central BuildKit for K8s runners**: For maximum build speed on self-hosted K8s runners (tak-k8s-ci), deploy a central BuildKit daemon. This provides:
  1. **Persistent layer cache** - no cold starts, layers cached across all builds
  2. **Base image cache** - `FROM` images cached, no re-pull each build
  3. **Shared across runners** - both Bitbucket and GitHub runners use the same daemon
  
  To use with docker-build.yml, set `runs_on: tak-k8s-ci` to run on self-hosted K8s runners. The workflow will automatically try the central BuildKit at `tcp://buildkit.buildkit.svc.cluster.local:1234` before falling back to docker-container driver.
  
  Without central BuildKit, each build starts cold with no cache. Registry cache (`cache-from=type=registry`) helps but is slower than local cache due to network I/O.

- **ARC GitHub App requires Actions permission**: The GitHub documentation for ARC authentication (https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api) does NOT mention this, but the GitHub App **must** have **Actions: Read and write** permission under Repository Permissions. Without it, the listener receives no job events and runners sit idle showing "Waiting for a runner to pick up this job" forever, even though runners are connected and listening. Symptoms:
  - Listener logs show `"assigned job": 0` continuously
  - Runner logs show "Connected to GitHub" and "Listening for Jobs"
  - GitHub UI shows "Waiting for a runner to pick up this job"
  
  Fix: Go to GitHub App settings → Permissions → Repository permissions → Actions → set to "Read and write".
