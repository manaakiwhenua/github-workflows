// Example docker-bake.hcl for consumer repositories
//
// This file defines the build targets for your Docker images.
// The reusable workflow provides REGISTRY_PREFIX and IMAGE_TAG variables.

// Variables provided by the build workflow
variable "REGISTRY_PREFIX" {
  description = "Registry path prefix (e.g., artifactory.example.com/docker/mwlr-private/my-app)"
}

variable "IMAGE_TAG" {
  description = "Image tag (e.g., 42-abc123def)"
}

// Optional: Git metadata for OCI labels
variable "GIT_ORIGIN" {
  default = ""
}

variable "GIT_REVISION" {
  default = ""
}

// Default target group - builds all targets
group "default" {
  targets = ["app", "worker"]
}

// Shared configuration for all targets
target "_common" {
  platforms = ["linux/amd64"]
  labels = {
    "org.opencontainers.image.source"   = "${GIT_ORIGIN}"
    "org.opencontainers.image.revision" = "${GIT_REVISION}"
  }
}

// Main application
target "app" {
  inherits   = ["_common"]
  context    = "."
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY_PREFIX}/app:${IMAGE_TAG}"]
}

// Background worker
target "worker" {
  inherits   = ["_common"]
  context    = "."
  dockerfile = "Dockerfile.worker"
  tags       = ["${REGISTRY_PREFIX}/worker:${IMAGE_TAG}"]
}

// Example: Build with secrets (e.g., private package registry)
// target "app-with-secrets" {
//   inherits   = ["app"]
//   secret     = ["type=env,id=ARTIFACTORY_TOKEN"]
// }

// Example: Multi-stage build with different context
// target "frontend" {
//   inherits   = ["_common"]
//   context    = "./frontend"
//   dockerfile = "Dockerfile"
//   tags       = ["${REGISTRY_PREFIX}/frontend:${IMAGE_TAG}"]
// }
