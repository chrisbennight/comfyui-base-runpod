# comfyui-runpod

Slim ComfyUI image for [RunPod](https://www.runpod.io/), tailored for video (Wan / LTX) and image (Flux / SDXL / Anima) workflows. Models live on a RunPod **Network Volume** mounted at `/workspace`, so they persist across pod swaps and don't need to be re-downloaded.

Forked from [`runpod-workers/comfyui-base`](https://github.com/runpod-workers/comfyui-base).

## Images

Pulled from GitHub Container Registry — public, no login required:

| Tag | When to use |
|---|---|
| `ghcr.io/chrisbennight/comfyui-runpod:cu128` | RTX 30/40 series, A100, H100, L40S — most RunPod GPUs |
| `ghcr.io/chrisbennight/comfyui-runpod:cu130` | RTX 5090, B200, anything Blackwell (driver 575+) |
| `ghcr.io/chrisbennight/comfyui-runpod:latest` | Alias for `:cu128` |
| `ghcr.io/chrisbennight/comfyui-runpod:vX.Y.Z-cu128` | Pinned release |
| `ghcr.io/chrisbennight/comfyui-runpod:vX.Y.Z-cu130` | Pinned release, Blackwell |

The `cu130` image uses CUDA 13.0 + PyTorch cu130 wheels and runs on Blackwell as well as Hopper/Ada with a recent driver. Pick whichever matches your pod's GPU.

## RunPod template

Recommended template settings:

| Field | Value |
|---|---|
| Container image | `ghcr.io/chrisbennight/comfyui-runpod:cu128` (or `:cu130`) |
| Container disk | 20 GB (just for transient working files) |
| Volume disk | **0 GB** — use a Network Volume instead (see below) |
| Network Volume | Attach to `/workspace` (size = your model library + outputs) |
| Exposed HTTP ports | `8188` |
| Exposed TCP ports | `22` |
| Environment | `PUBLIC_KEY=<your ssh key>` (optional but recommended) |
| Environment | `BOOTSTRAP_MODELS=1` (optional — runs `download-models.sh` on first boot) |

A 100 GB Network Volume is enough for Anima + a few Flux/Wan/LTX checkpoints. Network Volumes are pinned to a data center, so when you spin up new pods, request the same DC.

## Ports

- `8188` — ComfyUI (directly, or behind Caddy if `ALLOWED_IPS` is set — see below)
- `22` — SSH (set `PUBLIC_KEY` env or check the pod log for a one-time root password)

> JupyterLab (8888) and FileBrowser (8080) are intentionally **not** included — RunPod's web UI provides equivalent file browsing and a web terminal, and dropping them removes ~850 MB from the image.

## Access control

ComfyUI has no built-in authentication. By default this image binds ComfyUI to `127.0.0.1` so the only way in is an SSH tunnel:

```bash
ssh -L 8188:localhost:8188 root@<pod>.proxy.runpod.net
# then visit http://localhost:8188 in your browser
```

For browser access from a known IP (your home WAN IP, an office IP, a VPN exit), set `ALLOWED_IPS` on the pod and a baked Caddy reverse proxy goes in front with a source-IP allowlist:

| `ALLOWED_IPS` value | Effect |
|---|---|
| unset | Caddy not started. ComfyUI on `127.0.0.1:8188`. SSH-tunnel only. |
| `203.0.113.42` | Caddy on `0.0.0.0:8188`, allow only that IP. ComfyUI on `127.0.0.1:8189`. |
| `203.0.113.42 198.51.100.0/24` | Multiple IPs / CIDRs, space-separated. |

**First-deploy verification.** RunPod's HTTPS proxy terminates TLS at their edge and forwards plain HTTP to the pod, so Caddy reads the real client IP from `X-Forwarded-For` (trusting RFC1918 proxies). To confirm Caddy is seeing your actual home IP — not RunPod's internal proxy IP — hit the debug endpoint after deploy:

```
https://<pod-id>-8188.proxy.runpod.net/__whoami
```

It always returns 200 with `client_ip`, `remote_ip`, the raw `X-Forwarded-For` header, and the parsed `ALLOWED_IPS` env. If `client_ip` doesn't match your home WAN IP (check at `ifconfig.me`), update `ALLOWED_IPS` accordingly.

**What you give up.** `--require-hashes` doesn't apply here — Caddy itself is pinned by version + SHA256, but its config is loaded at runtime. The allowlist is exactly as strong as the secrecy of `ALLOWED_IPS` and RunPod's proxy isolation.

## Pre-installed custom nodes

| Node | Purpose |
|---|---|
| ComfyUI-Manager | Install/update more nodes from the UI |
| ComfyUI-KJNodes | kijai's general utility nodes |
| rgthree-comfy | Workflow QoL (power-prompt, fast groups) |
| ComfyUI-Custom-Scripts | pythongosssss QoL (favorites, autocomplete) |
| ComfyUI-Impact-Pack | FaceDetailer, regional prompting |
| ComfyUI-Inspire-Pack | Workflow batching, prompt utilities |
| comfyui_controlnet_aux | ControlNet preprocessors |
| was-node-suite-comfyui | Image utility nodes |
| ComfyUI-VideoHelperSuite | Video I/O (mp4 muxing, frame loaders) |
| ComfyUI-WanVideoWrapper | Wan 2.x video |
| ComfyUI-LTXVideo | LTX-Video |
| ComfyUI-GGUF | Quantized model loaders (essential for video on ≤24 GB VRAM) |

Anything else you install via ComfyUI-Manager lives under `/workspace/ComfyUI/custom_nodes/` and persists with the volume.

## Models

The image ships **without** model weights. On a fresh Network Volume, two options:

### Option A — opt-in bootstrap script

Set `BOOTSTRAP_MODELS=1` on the pod. On first boot, `download-models.sh` pulls a default set into `/workspace/ComfyUI/models/` using `aria2c`:

| Set | Files | Approx size |
|---|---|---|
| `anima` | Cosmos-derived 2B base + Qwen text encoder + Qwen VAE | ~6 GB |
| `flux-dev-fp8` | Flux.1-dev fp8 single-file | ~12 GB |
| `wan-gguf` | Wan 2.2 14B I2V Q5_K_M + UMT5 + Wan VAE | ~14 GB |
| `ltx-video` | LTX-Video 0.9.5 + T5 XXL | ~10 GB |

Customize the set with `MODEL_SETS=anima,wan-gguf` (default: all four). Pass `HF_TOKEN=hf_xxx` for gated models. Re-runs are idempotent — files that exist are skipped.

To run the bootstrap manually after the pod is up:

```bash
# inside the pod
MODEL_SETS=anima,wan-gguf bash /usr/local/bin/download-models.sh
```

### Option B — bring your own

```bash
cd /workspace/ComfyUI/models/diffusion_models
huggingface-cli download <repo> <file> --local-dir .
# or
aria2c -x 8 <url>
```

Drop files into the standard ComfyUI subdirectories: `checkpoints/`, `diffusion_models/`, `vae/`, `text_encoders/`, `clip/`, `loras/`, `upscale_models/`, etc.

## Custom ComfyUI args

Edit `/workspace/comfyui_args.txt` (one flag per line, `#` comments ignored):

```
--max-batch-size 8
--preview-method auto
--reserve-vram 1.5
```

Restart the pod (or `kill` ComfyUI inside the pod) for changes to apply.

## Directory layout (on the Network Volume)

```
/workspace/
├── ComfyUI/
│   ├── models/         # all model weights — persists across pods
│   ├── output/         # generated images / videos
│   ├── user/           # workflows, settings, Manager cache
│   ├── custom_nodes/   # baked nodes + anything Manager installs
│   └── .venv/          # python venv (uses --system-site-packages)
├── .cache/
│   ├── huggingface/    # HF_HOME — transformers/diffusers cache
│   └── torch/          # TORCH_HOME — torch.hub cache
└── comfyui_args.txt    # extra CLI flags for ComfyUI
```

## Environment variables

| Var | Purpose |
|---|---|
| `PUBLIC_KEY` | SSH public key for root. If unset, a random root password is generated and printed to logs. |
| `BOOTSTRAP_MODELS` | Set to `1` to run `download-models.sh` on first boot. |
| `MODEL_SETS` | Comma-separated set names for the bootstrap (`anima,flux-dev-fp8,flux-dev-fp16,wan-gguf,ltx-video,upscalers`). |
| `ALLOWED_IPS` | If set, start Caddy as a reverse proxy in front of ComfyUI with a source-IP allowlist (see Access control below). If unset, ComfyUI binds to `127.0.0.1` only and is reachable via SSH tunnel. |
| `HF_TOKEN` | Hugging Face token, used by the bootstrap and propagated to SSH/Jupyter shells. |
| `HF_HOME` | Hugging Face cache root. Defaults to `/workspace/.cache/huggingface` so cached model weights survive pod swaps. |
| `TORCH_HOME` | PyTorch hub cache root. Defaults to `/workspace/.cache/torch` for the same reason. |
| `COMFYUI_MODELS_DIR` | Override the bootstrap target dir (default `/workspace/ComfyUI/models`). |

## Local development

```bash
# Build the cu128 image into the local docker daemon
docker buildx bake -f docker-bake.hcl dev

# Run with a host-mounted workspace
docker run --rm --gpus all \
  -p 8188:8188 -p 2222:22 \
  -e PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
  -v "$PWD/workspace:/workspace" \
  ghcr.io/chrisbennight/comfyui-runpod:dev
```

## License

GPL-3.0 (inherited from upstream).
