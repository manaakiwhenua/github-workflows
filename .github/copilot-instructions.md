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

- **Terminal commands with cd**: When running terminal commands, always `cd` to the correct directory as a **separate command** before running other commands. The terminal tool may simplify chained commands and strip the `cd` portion, causing commands to run in the wrong directory.
