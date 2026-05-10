# comfyui-runpod — developer notes

How to work in this repo: build targets, runtime behavior, environment, dependency management, customization, gates, and troubleshooting.

## Stack overview

- **Base OS**: Ubuntu 24.04
- **GPU stack**:
  - `cu128` image: CUDA 12.8 + PyTorch cu128 wheels (RTX 30/40, A100, H100, L40S, …)
  - `cu130` image: CUDA 13.0 + PyTorch cu130 wheels (RTX 5090 / Blackwell / B200, also runs on Hopper/Ada with driver 575+)
- **Python**: 3.12 (system default)
- **Package manager**: pip + pip-tools (lockfile generated at build time with `pip-compile --generate-hashes`)
- **Tools bundled**: OpenSSH server (port 22), FFmpeg (NVENC), `aria2`, `huggingface_hub[cli]`, common CLI tools
- **App**: ComfyUI + 12 pre-installed custom nodes (see README)

JupyterLab and FileBrowser are intentionally **not** bundled. RunPod's web UI handles file browsing and provides a web terminal; we save ~850 MB by dropping them.

## Repository layout

- `Dockerfile` — single multi-stage Dockerfile for both CUDA variants (controlled by build args)
- `start.sh` — runtime entrypoint
- `docker-bake.hcl` — buildx bake targets and **all pinned versions** (single source of truth)
- `scripts/fetch-hashes.sh` — query GitHub for latest custom node SHAs, output HCL-ready blocks
- `scripts/download-models.sh` — opt-in model bootstrap (runs on `BOOTSTRAP_MODELS=1` or invoked manually)
- `scripts/prebake-manager-cache.py` — pre-fetches ComfyUI-Manager registry at build time
- `.github/workflows/release.yml` — tag-driven release build (pushes to GHCR)
- `.github/workflows/dev.yml` — manual dev build (pushes `:dev-cu128` / `:dev-cu130`)

At runtime the container expects a RunPod **Network Volume** (or pod volume) mounted at `/workspace`:

- `/workspace/ComfyUI/` — ComfyUI checkout, venv, models, outputs, custom_nodes
- `/workspace/comfyui_args.txt` — optional line-delimited ComfyUI CLI flags

## Build targets

Bake targets in `docker-bake.hcl`:

| Target | Pushes | Use |
|---|---|---|
| `cu128` | `:vX.Y.Z-cu128`, `:cu128`, `:latest` | Production CUDA 12.8 |
| `cu130` | `:vX.Y.Z-cu130`, `:cu130` | Production CUDA 13.0 (Blackwell) |
| `dev` | local `:dev` | Local dev (loads into local docker daemon) |
| `devpush-cu128` | `:dev-cu128` | CI dev build, cu128 |
| `devpush-cu130` | `:dev-cu130` | CI dev build, cu130 |

`IMAGE_REF` defaults to `ghcr.io/chrisbennight/comfyui-runpod`; override via env if forking.

```bash
# Local dev image
docker buildx bake -f docker-bake.hcl dev

# Push a release (CI does this on tag push)
TAG=v0.2.0 docker buildx bake -f docker-bake.hcl cu128 cu130 --push
```

### Provenance labels

All targets inherit a `labels` block in `target "common"` that sets the standard [OCI image annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md):

- `org.opencontainers.image.title`, `description`, `source`, `url`, `licenses` — hard-coded
- `org.opencontainers.image.version` — `${TAG}` (git tag for releases, `dev` for dev builds)
- `org.opencontainers.image.revision` — `${GIT_SHA}` (commit SHA the image was built from)
- `org.opencontainers.image.created` — `${BUILD_DATE}` (RFC3339 timestamp)

The CI workflows populate `GIT_SHA` and `BUILD_DATE` automatically. For local builds these stay empty.

To inspect a published image:

```bash
docker buildx imagetools inspect ghcr.io/chrisbennight/comfyui-runpod:v0.1.0-cu128
docker pull ghcr.io/chrisbennight/comfyui-runpod:v0.1.0-cu128
docker inspect ghcr.io/chrisbennight/comfyui-runpod:v0.1.0-cu128 \
  --format '{{json .Config.Labels}}' | jq
```

### Tag verification (release workflow)

`release.yml` runs a `Verify tag points at HEAD and tree is clean` step before any image is built. It fails the run if:

- The resolved version isn't a real git tag, OR
- The tag doesn't point at `HEAD`, OR
- The working tree has uncommitted changes.

This closes the `workflow_dispatch` footgun where you could previously publish a `:v0.1.0-cu128` image without ever creating a `v0.1.0` git tag. To do a "manual" release now: push the tag, then either let the tag-push trigger fire automatically or use `workflow_dispatch` with the tag selected as the ref.

## Runtime behavior

`start.sh`:

1. Set up SSH. If `PUBLIC_KEY` is set, install it for root; otherwise generate a random root password and print it.
2. Ensure `/workspace` exists, then point `HF_HOME` and `TORCH_HOME` at `/workspace/.cache/{huggingface,torch}` (creating the dirs). Honors user-provided values if already set.
3. Propagate selected env vars (`RUNPOD_*`, `CUDA*`, `LD_LIBRARY_PATH`, `PYTHONPATH`, `HF_*`, `TORCH_HOME`) into `/etc/environment`, PAM, and `~/.ssh/environment` so SSH/non-interactive shells inherit them.
4. Ensure `/workspace/comfyui_args.txt` exists.
5. **First boot**: `cp -r /opt/comfyui-baked /workspace/ComfyUI`, then `python3.12 -m venv --system-site-packages /workspace/ComfyUI/.venv` and `python -m ensurepip`.
6. **Subsequent boots**: just activate the existing venv.
7. If `BOOTSTRAP_MODELS=1`, run `download-models.sh` (idempotent — skips files that already exist).
8. Launch ComfyUI in foreground with `--listen 0.0.0.0 --port 8188 --enable-cors-header` plus anything in `comfyui_args.txt`.
9. If ComfyUI exits, `sleep infinity` keeps the container alive so SSH stays accessible for debugging.

Custom nodes installed at runtime via ComfyUI-Manager land under `/workspace/ComfyUI/custom_nodes/` and persist with the volume.

## Ports

- `8188` — ComfyUI
- `22` — SSH

That's it. The image does **not** expose 8080 or 8888.

## Environment variables

| Var | Effect |
|---|---|
| `PUBLIC_KEY` | Adds an SSH authorized key for root. If unset, a random root password is generated. |
| `BOOTSTRAP_MODELS` | If `1`, run `download-models.sh` on first boot. |
| `MODEL_SETS` | Comma-separated set names (`anima,flux-dev-fp8,flux-dev-fp16,wan-gguf,ltx-video,upscalers`). Default: `anima,flux-dev-fp8,wan-gguf,ltx-video`. |
| `HF_TOKEN` | Hugging Face token for gated downloads; propagated to SSH/Jupyter shells. |
| `HF_HOME` | HF cache root. Defaults to `/workspace/.cache/huggingface` so weights cached by `transformers` / `diffusers` / `huggingface_hub` survive pod swaps. |
| `TORCH_HOME` | PyTorch hub cache root. Defaults to `/workspace/.cache/torch`. |
| `COMFYUI_MODELS_DIR` | Override the bootstrap target dir (default `/workspace/ComfyUI/models`). |
| RunPod-injected `RUNPOD_*` | Forwarded to interactive shells. |

## Dependency management

- All Python dependencies are installed at **build time** into the image's system site-packages with hash verification (`pip-compile --generate-hashes` + `pip install --require-hashes`).
- The runtime venv at `/workspace/ComfyUI/.venv` uses `--system-site-packages`, so it inherits torch/numpy/etc. from the image but lets the user `pip install` extras for new custom nodes without re-installing torch.
- Version pins live in `docker-bake.hcl`:
  - `COMFYUI_VERSION` — ComfyUI release tag.
  - `*_SHA` — commit SHA per custom node.
  - `TORCH_VERSION` / `TORCH_VERSION_CU130` — PyTorch versions per CUDA stack.
  - `CUDA_VERSION_DASH`, `TORCH_INDEX_SUFFIX` — controls which CUDA apt package and PyTorch wheel index the build uses.
- To refresh custom node SHAs to upstream HEAD: `GITHUB_TOKEN=… ./scripts/fetch-hashes.sh`, paste output back into `docker-bake.hcl`.
- Source archives are downloaded as zips (no `git clone` in the build).
- After Stage 1, custom nodes have local git repos initialized with upstream remotes pointing at the right URL — ComfyUI-Manager uses these to detect updates.

## Adding / removing a custom node

1. Pick a SHA via `scripts/fetch-hashes.sh` (after adding the repo to its `NODES` list).
2. Add a `*_SHA` `variable` block in `docker-bake.hcl`.
3. Add the matching `ARG` and `fetch …` / `init_repo …` calls in the Dockerfile.
4. Update the README's node table.

## Customization points

- `comfyui_args.txt` — one CLI arg per line, `#` comments allowed.
- Add/remove custom nodes — see above.
- Additional system packages — modify the runtime stage `apt-get install` block in the Dockerfile.
- Swap `download-models.sh` defaults — edit the `MODEL_SETS` default and the `fetch …` calls.
- Users can install more custom nodes at runtime via ComfyUI-Manager. Their dependencies persist in the volume's venv.

## Conventions

- Keep the image lean. Bake everything that can be baked.
- Pin everything. No floating refs in build inputs.
- Don't run pip / git / install scripts at startup. `start.sh` should only copy files, activate a venv, and exec ComfyUI.
- Don't change ports without a coordinated README + RunPod template update.
- Bash: `set -e` at the top, idempotent steps, explicit guards.

## Troubleshooting

- **ComfyUI not reachable on 8188**: check container logs (foreground), check `comfyui_args.txt` for typos.
- **GPU mismatch** (e.g. cu130 image on a non-Blackwell pod): switch tag to `:cu128`, or update the pod's host driver.
- **First start downloads taking forever**: this is the model bootstrap if `BOOTSTRAP_MODELS=1`. To stop it, unset the env or restart the pod after the first boot completes.
- **Custom node failed to import**: check `/workspace/ComfyUI/user/__manager/cache/.startup-script.log` for ComfyUI-Manager output, or run `python main.py` manually inside the venv.
- **No SSH password printed**: it's only generated when `PUBLIC_KEY` is unset. Either set `PUBLIC_KEY` or grep the pod log for `Generated root password`.

## License

GPL-3.0 (inherited from upstream `runpod-workers/comfyui-base`).
