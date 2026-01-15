// docker-bake.hcl for barcode-data-portal-mwlr
//
// Place this at the root of the barcode-data-portal-mwlr repository

variable "REGISTRY_PREFIX" {
  description = "Registry path prefix provided by build workflow"
}

variable "IMAGE_TAG" {
  description = "Image tag provided by build workflow"
}

variable "GIT_ORIGIN" {
  default = ""
}

variable "GIT_REVISION" {
  default = ""
}

group "default" {
  targets = ["fastapi-app", "socketserver-logging"]
}

target "_common" {
  platforms = ["linux/amd64"]
  labels = {
    "org.opencontainers.image.source"   = "${GIT_ORIGIN}"
    "org.opencontainers.image.revision" = "${GIT_REVISION}"
    "org.opencontainers.image.vendor"   = "Manaaki Whenua"
  }
}

target "fastapi-app" {
  inherits   = ["_common"]
  context    = "."
  dockerfile = "docker/Dockerfile"
  tags       = ["${REGISTRY_PREFIX}/fastapi-app:${IMAGE_TAG}"]
}

target "socketserver-logging" {
  inherits   = ["_common"]
  context    = "."
  dockerfile = "docker/Dockerfile.socketserver_logging"
  tags       = ["${REGISTRY_PREFIX}/socketserver-logging:${IMAGE_TAG}"]
}
