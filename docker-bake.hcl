variable "IMAGE_REF" {
  default = "ghcr.io/chrisbennight/comfyui-runpod"
}

variable "TAG" {
  default = "latest"
}

# === ComfyUI core ===
variable "COMFYUI_VERSION" {
  default = "v0.18.2"
}

# === Custom node pins (commit SHAs from scripts/fetch-hashes.sh) ===
variable "MANAGER_SHA" {
  default = "8079db221de4"
}
variable "KJNODES_SHA" {
  default = "fca78c93f034"
}
variable "RGTHREE_SHA" {
  default = "738105af5fb1"
}
variable "CUSTOM_SCRIPTS_SHA" {
  default = "609f3afaa74b"
}
variable "IMPACT_PACK_SHA" {
  default = "429d0159ad42"
}
variable "INSPIRE_PACK_SHA" {
  default = "d23db9aa544d"
}
variable "CONTROLNET_AUX_SHA" {
  default = "e8b689a513c3"
}
variable "WAS_SUITE_SHA" {
  default = "ea935d1044ae"
}
variable "VIDEOHELPER_SHA" {
  default = "2984ec4c4b93"
}
variable "WANVIDEO_SHA" {
  default = "d18cdb18597f"
}
variable "LTXVIDEO_SHA" {
  default = "2acf7af8991f"
}
variable "GGUF_SHA" {
  default = "6ea2651e7df6"
}

# === Caddy (reverse proxy with IP allowlist, used when ALLOWED_IPS env is set) ===
variable "CADDY_VERSION" {
  default = "2.11.2"
}
variable "CADDY_SHA256" {
  default = "94391dfefe1f278ac8f387ab86162f0e88d87ff97df367f360e51e3cda3df56f"
}

# === Build provenance (populated by CI from env; empty for local builds) ===
variable "GIT_SHA" {
  default = ""
}
variable "BUILD_DATE" {
  default = ""
}

# === PyTorch / CUDA ===
# Default image: CUDA 12.8 (cu128 wheels)
variable "TORCH_VERSION" {
  default = "2.10.0+cu128"
}
variable "TORCHVISION_VERSION" {
  default = "0.25.0+cu128"
}
variable "TORCHAUDIO_VERSION" {
  default = "2.10.0+cu128"
}

# Blackwell (RTX 5090 / B200) image: CUDA 13.0 (cu130 wheels)
variable "TORCH_VERSION_CU130" {
  default = "2.10.0+cu130"
}
variable "TORCHVISION_VERSION_CU130" {
  default = "0.25.0+cu130"
}
variable "TORCHAUDIO_VERSION_CU130" {
  default = "2.10.0+cu130"
}

group "default" {
  targets = ["dev"]
}

# Common settings shared by all targets (defaults to CUDA 12.8 / cu128)
target "common" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  labels = {
    "org.opencontainers.image.title"       = "comfyui-runpod"
    "org.opencontainers.image.description" = "Slim ComfyUI image for RunPod (video + image workflows)"
    "org.opencontainers.image.source"      = "https://github.com/chrisbennight/comfyui-base-runpod"
    "org.opencontainers.image.url"         = "https://github.com/chrisbennight/comfyui-base-runpod"
    "org.opencontainers.image.licenses"    = "GPL-3.0-or-later"
    "org.opencontainers.image.version"     = TAG
    "org.opencontainers.image.revision"    = GIT_SHA
    "org.opencontainers.image.created"     = BUILD_DATE
  }
  args = {
    COMFYUI_VERSION     = COMFYUI_VERSION
    MANAGER_SHA         = MANAGER_SHA
    KJNODES_SHA         = KJNODES_SHA
    RGTHREE_SHA         = RGTHREE_SHA
    CUSTOM_SCRIPTS_SHA  = CUSTOM_SCRIPTS_SHA
    IMPACT_PACK_SHA     = IMPACT_PACK_SHA
    INSPIRE_PACK_SHA    = INSPIRE_PACK_SHA
    CONTROLNET_AUX_SHA  = CONTROLNET_AUX_SHA
    WAS_SUITE_SHA       = WAS_SUITE_SHA
    VIDEOHELPER_SHA     = VIDEOHELPER_SHA
    WANVIDEO_SHA        = WANVIDEO_SHA
    LTXVIDEO_SHA        = LTXVIDEO_SHA
    GGUF_SHA            = GGUF_SHA
    TORCH_VERSION       = TORCH_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    CUDA_VERSION_DASH   = "12-8"
    TORCH_INDEX_SUFFIX  = "cu128"
    CADDY_VERSION       = CADDY_VERSION
    CADDY_SHA256        = CADDY_SHA256
  }
}

# Production image, CUDA 12.8 (covers RTX 30/40, A100, H100, L40S, etc.)
target "cu128" {
  inherits = ["common"]
  tags = [
    "${IMAGE_REF}:${TAG}-cu128",
    "${IMAGE_REF}:cu128",
    "${IMAGE_REF}:latest",
  ]
}

# Production image, CUDA 13.0 (RTX 5090 / Blackwell / B200)
target "cu130" {
  inherits = ["common"]
  tags = [
    "${IMAGE_REF}:${TAG}-cu130",
    "${IMAGE_REF}:cu130",
  ]
  args = {
    TORCH_VERSION       = TORCH_VERSION_CU130
    TORCHVISION_VERSION = TORCHVISION_VERSION_CU130
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION_CU130
    CUDA_VERSION_DASH   = "13-0"
    TORCH_INDEX_SUFFIX  = "cu130"
  }
}

# Local dev build (loaded into the local docker daemon, not pushed)
target "dev" {
  inherits = ["common"]
  tags     = ["${IMAGE_REF}:dev"]
  output   = ["type=docker"]
}

# CI-pushed dev tags (separate from :latest so manual testing doesn't override prod)
target "devpush-cu128" {
  inherits = ["common"]
  tags     = ["${IMAGE_REF}:dev-cu128"]
}

target "devpush-cu130" {
  inherits = ["cu130"]
  tags     = ["${IMAGE_REF}:dev-cu130"]
}
