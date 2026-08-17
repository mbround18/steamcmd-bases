// docker-bake.hcl - buildx bake definitions for the three steamcmd-bases images.
//
// Usage:
//   docker buildx bake                 # build base, wine, proton (loads into local docker)
//   docker buildx bake proton          # build a single target
//   docker buildx bake --push          # build and push all targets + cache
//   TAG=v1.2.3 docker buildx bake --push
//
// Note: the wine/proton targets COPY target/release/test-exe into the image,
// so `cargo build --release --target x86_64-unknown-linux-gnu` must have run
// first (see Makefile).

variable "REGISTRY_IMAGE" {
  default = "mbround18/steamcmd"
}

// GITHUB_SHA is auto-exported by GitHub Actions runners on every job -
// empty outside CI, so this is harmless locally. (Proper version-tag
// releases, e.g. v1.2.3, are handled by .github/workflows/deployer.yaml's
// reusable workflow, not by this file.)
variable "GITHUB_SHA" {
  default = ""
}

// Explicit TAG (the Makefile passes the git short SHA locally) always wins.
// With nothing set: the short commit SHA in CI, or "latest" outside it.
// Every target also tags `-latest` unconditionally, so an unset TAG never
// leaves an image untagged either way.
variable "TAG" {
  default = notequal(GITHUB_SHA, "") ? substr(GITHUB_SHA, 0, 7) : "latest"
}

// Override to pin an exact GE-Proton release for reproducible builds,
// e.g. GE-Proton9-20. Defaults to whatever is newest on GitHub at build time.
variable "PROTON_VERSION" {
  default = "latest"
}

group "default" {
  targets = ["base", "wine", "proton"]
}

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  args = {
    BUILDKIT_INLINE_CACHE = "1"
  }
}

target "base" {
  inherits = ["_common"]
  target   = "base"
  tags = [
    "${REGISTRY_IMAGE}:base-${TAG}",
    "${REGISTRY_IMAGE}:base-latest",
  ]
  cache-from = ["type=registry,ref=${REGISTRY_IMAGE}:base-cache"]
  cache-to   = ["type=registry,ref=${REGISTRY_IMAGE}:base-cache,mode=max"]
}

target "wine" {
  inherits = ["_common"]
  target   = "wine"
  tags = [
    "${REGISTRY_IMAGE}:wine-${TAG}",
    "${REGISTRY_IMAGE}:wine-latest",
  ]
  cache-from = ["type=registry,ref=${REGISTRY_IMAGE}:wine-cache"]
  cache-to   = ["type=registry,ref=${REGISTRY_IMAGE}:wine-cache,mode=max"]
}

target "proton" {
  inherits = ["_common"]
  target   = "proton"
  args = {
    PROTON_VERSION = "${PROTON_VERSION}"
  }
  tags = [
    "${REGISTRY_IMAGE}:proton-${TAG}",
    "${REGISTRY_IMAGE}:proton-latest",
  ]
  cache-from = ["type=registry,ref=${REGISTRY_IMAGE}:proton-cache"]
  cache-to   = ["type=registry,ref=${REGISTRY_IMAGE}:proton-cache,mode=max"]
}
