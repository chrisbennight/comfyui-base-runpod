#!/usr/bin/env bash
# download-models.sh — Opt-in bootstrap for the model set this image targets.
#
# Trigger this either by setting BOOTSTRAP_MODELS=1 on the pod (so start.sh
# runs it on boot) or by invoking it manually:
#
#   bash /usr/local/bin/download-models.sh                # download default set
#   MODEL_SETS="anima,wan-gguf" bash /usr/local/bin/download-models.sh
#
# Models land in /workspace/ComfyUI/models on the mounted Network Volume
# so they persist across pod swaps. Re-running is idempotent: aria2c will
# skip files that already exist.
#
# Storage budget (rough):
#   anima       ~6  GB  (base + qwen text encoder + qwen VAE)
#   flux-dev   ~24  GB  (fp8 ~12GB; full fp16 ~24GB — defaults to fp8)
#   wan-gguf   ~14  GB  (Wan 2.2 14B Q5_K_M)
#   ltx-video  ~10  GB  (LTX 0.9.5)
#
# Override the destination root with COMFYUI_MODELS_DIR if you want.

set -euo pipefail

MODELS_ROOT="${COMFYUI_MODELS_DIR:-/workspace/ComfyUI/models}"
MODEL_SETS="${MODEL_SETS:-anima,flux-dev-fp8,wan-gguf,ltx-video}"

mkdir -p \
  "$MODELS_ROOT/diffusion_models" \
  "$MODELS_ROOT/checkpoints" \
  "$MODELS_ROOT/text_encoders" \
  "$MODELS_ROOT/clip" \
  "$MODELS_ROOT/vae" \
  "$MODELS_ROOT/unet" \
  "$MODELS_ROOT/loras" \
  "$MODELS_ROOT/upscale_models"

# aria2c: 8 connections per file, resume on partial, skip if file exists
fetch() {
  local url="$1" dest_dir="$2" filename="${3:-}"
  if [ -z "$filename" ]; then
    filename="$(basename "$url")"
  fi
  if [ -f "$dest_dir/$filename" ]; then
    echo "  [skip] $filename already exists"
    return 0
  fi
  echo "  [get]  $filename"
  local hf_header=()
  if [ -n "${HF_TOKEN:-}" ]; then
    hf_header=(--header="Authorization: Bearer ${HF_TOKEN}")
  fi
  aria2c -x 8 -s 8 -k 1M --console-log-level=warn \
    --auto-file-renaming=false --allow-overwrite=false \
    "${hf_header[@]}" \
    -d "$dest_dir" -o "$filename" "$url"
}

has_set() {
  echo ",${MODEL_SETS}," | grep -q ",$1,"
}

echo "[bootstrap] models root:  $MODELS_ROOT"
echo "[bootstrap] model sets:   $MODEL_SETS"

if has_set anima; then
  echo "[bootstrap] >> Anima (Cosmos-Predict2 2B + Qwen text encoder + Qwen VAE)"
  fetch "https://huggingface.co/circlestone-labs/Anima/resolve/main/anima-preview3-base.safetensors" \
        "$MODELS_ROOT/diffusion_models"
  fetch "https://huggingface.co/circlestone-labs/Anima/resolve/main/qwen_3_06b_base.safetensors" \
        "$MODELS_ROOT/text_encoders"
  fetch "https://huggingface.co/circlestone-labs/Anima/resolve/main/qwen_image_vae.safetensors" \
        "$MODELS_ROOT/vae"
fi

if has_set flux-dev-fp8; then
  echo "[bootstrap] >> Flux.1 dev (fp8 single-file)"
  fetch "https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors" \
        "$MODELS_ROOT/checkpoints"
fi

if has_set flux-dev-fp16; then
  echo "[bootstrap] >> Flux.1 dev fp16 (24GB) — only enable on big VRAM"
  fetch "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors" \
        "$MODELS_ROOT/diffusion_models"
  fetch "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
        "$MODELS_ROOT/clip"
  fetch "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
        "$MODELS_ROOT/clip"
  fetch "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" \
        "$MODELS_ROOT/vae" "flux_ae.safetensors"
fi

if has_set wan-gguf; then
  echo "[bootstrap] >> Wan 2.2 (14B i2v Q5_K_M GGUF) + UMT5 text encoder + Wan VAE"
  fetch "https://huggingface.co/city96/Wan2.2-I2V-A14B-gguf/resolve/main/Wan2.2-I2V-A14B-Q5_K_M.gguf" \
        "$MODELS_ROOT/diffusion_models"
  fetch "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        "$MODELS_ROOT/text_encoders"
  fetch "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
        "$MODELS_ROOT/vae"
fi

if has_set ltx-video; then
  echo "[bootstrap] >> LTX-Video 0.9.5"
  fetch "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.safetensors" \
        "$MODELS_ROOT/checkpoints"
  fetch "https://huggingface.co/Lightricks/LTX-Video/resolve/main/text_encoders/PixArt-XL-2-1024-MS/text_encoder/model.safetensors" \
        "$MODELS_ROOT/text_encoders" "ltx_t5xxl.safetensors"
fi

if has_set upscalers; then
  echo "[bootstrap] >> Upscalers (4x_NMKD-Siax + 4x-UltraSharp)"
  fetch "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth" \
        "$MODELS_ROOT/upscale_models"
  fetch "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth" \
        "$MODELS_ROOT/upscale_models"
fi

echo "[bootstrap] done."
