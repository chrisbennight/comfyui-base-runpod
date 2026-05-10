# AGENTS.md

Guidance for AI agents (and humans) working in this repo.

## Intent

This is a slim ComfyUI container image purpose-built for **RunPod pods backed by a Network Volume**. It is a fork of [`runpod-workers/comfyui-base`](https://github.com/runpod-workers/comfyui-base) with three opinionated changes:

1. **Stripped down**: only ComfyUI + SSH. No JupyterLab, no FileBrowser. RunPod's web UI already provides file browsing and a terminal.
2. **Network-volume-first**: workspace flattened to `/workspace/ComfyUI/...`. The volume is the unit of persistence — models, custom nodes, venv, outputs, and user settings all live on it and survive pod swaps.
3. **Tailored node loadout**: targets video (Wan / LTX) and image (Flux / SDXL / Anima) workflows. Not a general-purpose ComfyUI bundle.

Published publicly to GHCR as `ghcr.io/chrisbennight/comfyui-runpod`. Two CUDA variants (`:cu128` and `:cu130`) cover most RunPod GPUs.

## File map

| Path | What it owns |
|---|---|
| `Dockerfile` | Multi-stage build. Stage 1 fetches sources, generates a hashed lockfile, installs Python deps. Stage 2 is the runtime image. Same Dockerfile for both CUDA variants — controlled by `CUDA_VERSION_DASH` and `TORCH_INDEX_SUFFIX` build args. |
| `docker-bake.hcl` | **Single source of truth** for every pinned version (ComfyUI, custom node SHAs, PyTorch, CUDA), and for image tags. Build targets: `cu128`, `cu130`, `dev`, `devpush-cu128`, `devpush-cu130`. |
| `start.sh` | Runtime entrypoint. Sets up SSH, propagates env vars, copies baked ComfyUI to the volume on first boot, creates the venv, optionally runs the model bootstrap, then `exec`s ComfyUI. |
| `scripts/fetch-hashes.sh` | Queries the GitHub API for upstream HEAD SHAs of each pinned custom node and prints HCL-ready `variable` blocks. |
| `scripts/download-models.sh` | Opt-in model bootstrap (Anima, Flux dev fp8, Wan 2.2 GGUF, LTX-Video, upscalers). Idempotent; uses `aria2c`. Triggered by `BOOTSTRAP_MODELS=1` or invoked manually inside the pod. |
| `scripts/prebake-manager-cache.py` | Pre-fetches the ComfyUI-Manager registry at build time so first cold start doesn't paginate ~127 requests against `api.comfy.org`. |
| `caddy/Caddyfile` | Baked config for the Caddy reverse proxy. Started by `start.sh` only when `ALLOWED_IPS` is set on the pod. Enforces a source-IP allowlist using `X-Forwarded-For` (since RunPod's HTTPS proxy terminates TLS before the pod). Exposes a `/__whoami` debug endpoint that always returns the detected client IP. |
| `.github/workflows/release.yml` | Tag-driven build that pushes `:vX.Y.Z-cu128`, `:cu128`, `:latest`, `:vX.Y.Z-cu130`, `:cu130` to GHCR. Auths with `GITHUB_TOKEN` (no DockerHub secrets). Three jobs: `verify` (tag-points-at-HEAD check), `build` (matrix cu128/cu130 on separate runners — sequential builds on one runner ran out of disk), `release-notes` (creates the GitHub Release after both builds push). |
| `.github/workflows/dev.yml` | Manual workflow that pushes `:dev-cu128` and `:dev-cu130` without touching `:latest`. |
| `.github/workflows/pr-build.yml` | Automatic on every PR against `main`. Builds both variants in parallel without pushing — merge gate. Uses GHA cache so iterative pushes on the same PR are fast. |
| `docs/context.md` | Detailed dev notes (build targets, ports, env vars, troubleshooting). Read this before making non-trivial changes. |
| `CHANGELOG.md` | Has a "fork divergence" section at the top documenting how this image differs from upstream `runpod-workers/comfyui-base`. |

## Architecture invariants

These are load-bearing — break them and the image stops working as designed.

- **`docker-bake.hcl` owns every version pin.** The Dockerfile declares `ARG` names but their defaults come from bake. Don't hard-code versions in the Dockerfile.
- **No runtime installs.** `start.sh` must never call `pip install`, `git clone`, or run a node's `install.py`. All Python deps are baked into the image's system site-packages at build time with hash verification. The runtime venv uses `--system-site-packages` so it inherits torch/numpy etc.; users can still `pip install` extras into the venv for new custom nodes installed via Manager.
- **Workspace path is `/workspace/ComfyUI`.** Don't reintroduce the old `/workspace/runpod-slim/` subdirectory. RunPod templates and Network Volumes are configured around `/workspace`.
- **One Dockerfile, both CUDA variants.** Don't fork into `Dockerfile.cu130`. The build args handle it.
- **Source archives, not `git clone`.** Build inputs are pinned tarballs from GitHub. After fetch, we `git init` each repo and add an `origin` remote so ComfyUI-Manager can detect updates — but the build itself never depends on git connectivity.
- **Ports are `8188` (ComfyUI or Caddy) and `22` (SSH) only.** Don't reopen 8080 or 8888 without updating the README, the RunPod template guidance, and removing the matching service rationale from `docs/context.md`. Internally, when `ALLOWED_IPS` is set, Caddy holds `0.0.0.0:8188` and ComfyUI moves to `127.0.0.1:8189` — the external port stays `8188` either way.
- **No built-in auth.** ComfyUI has no login. The image's two access modes are: SSH-tunnel only (default) or Caddy IP allowlist (`ALLOWED_IPS` set). Don't add public, unauthenticated exposure as a default. If a change makes ComfyUI reachable from `0.0.0.0` without an allowlist or auth in front, that's a regression — call it out loudly.
- **Container stays alive after ComfyUI exits.** `start.sh` does `wait $COMFY_PID || true` followed by `sleep infinity` so SSH stays accessible for debugging.

## Common change recipes

### Add a custom node

Touches four files, in this order:

1. `scripts/fetch-hashes.sh` — add `<owner/repo>|<NEW_VAR_NAME>` to the `NODES` list.
2. Run `GITHUB_TOKEN=<pat> ./scripts/fetch-hashes.sh` and copy the new `variable` block into `docker-bake.hcl`. Add the var to the `args = { ... }` block in `target "common"`.
3. `Dockerfile` — add an `ARG <NEW_VAR_NAME>`, a `fetch …` line in the source-download `RUN`, and an `init_repo …` line in the git-init `RUN`.
4. `README.md` — add a row to the node table. Update `CHANGELOG.md`.

### Remove a custom node

Reverse of the above. Don't forget to remove from the README table and add a CHANGELOG note.

### Bump pinned versions

- ComfyUI / PyTorch / CUDA / FileBrowser-equivalent / etc. → edit the `variable` block in `docker-bake.hcl`.
- All node SHAs at once → run `scripts/fetch-hashes.sh` and paste output back.

### Add/remove a system package

Edit the runtime stage `apt-get install` block in `Dockerfile`. The builder stage has its own minimal set — only add there if it's needed for the wheel install.

### Change the model bootstrap

Edit `scripts/download-models.sh`. Each set is gated by `has_set <name>`. Default sets are listed in the top comment and in `MODEL_SETS=` default. Keep it idempotent (skip on existing files) and don't bake credentials.

## Branch and PR policy

**Never push directly to `main`.** Every change lands via a pull request, regardless of size.

- Create a branch (`feat/short-name`, `fix/short-name`, `chore/short-name` — pick whichever fits).
- Open a PR against `main`.
- Use the PR template at [`.github/pull_request_template.md`](.github/pull_request_template.md). It's required, not aspirational — agents and humans both fill out:
  - **Intent**: what the PR is trying to achieve.
  - **High-level approach**: the shape of the solution in 2-5 sentences.
  - **Design considerations**: alternatives weighed, options not taken, why this direction.
  - **Flags / concerns / follow-ups**: anything not fully settled, anything that becomes more important if this lands.
  - **Validation**: what was actually run to confirm it works.
  - **References**: external docs, upstream PRs, model cards.

The template exists because this repo is small and personal but published — context has to live somewhere durable. Commit messages aren't enough; the PR description is the canonical record of *why*.

If a PR is genuinely trivial (typo, comment fix), say so in the Intent section and leave the rest minimal — but use the template structure.

Every PR also triggers the **PR Build Verify** workflow which builds both `cu128` and `cu130` variants. The build must succeed before merge. To make this enforced, configure branch protection in `Settings → Branches → Branch protection rules` for `main` to require the `Build (cu128)` and `Build (cu130)` checks; otherwise the workflow runs but failures don't block merge.

## Validate before pushing

The image is large (~10 GB) and pulls ~5 GB of wheels — local builds are slow. Use these gates instead of full builds when iterating:

```bash
# 1. Bake-file validates and resolves args
docker buildx bake --print -f docker-bake.hcl cu128 cu130 dev

# 2. Shell scripts parse cleanly
bash -n start.sh scripts/fetch-hashes.sh scripts/download-models.sh

# 3. Dockerfile syntax (cheap)
docker buildx build --check -f Dockerfile .
```

For real validation, the **PR Build Verify** workflow runs automatically on every PR against `main`. It builds both `cu128` and `cu130` variants in parallel without pushing, using GHA cache so re-builds on the same branch are fast. A failing build blocks the merge.

If you need to iterate before opening a PR, trigger the **Dev Build** workflow manually with `push=true`. It builds both variants on GHA and pushes `:dev-cu{128,130}`.

Avoid running `docker buildx bake dev` locally unless you actually need to iterate on something the bake/syntax checks can't catch — it'll re-pull all the wheels.

## Releasing

Tag-driven. `git tag v0.X.Y && git push origin v0.X.Y` triggers `release.yml` which builds and pushes both variants to GHCR. The workflow uses `GITHUB_TOKEN` — no manual secret setup.

`docker-bake.hcl` reads the version from the `TAG` env var (set in the workflow). Don't override `tags` via `--set` in the workflow; tag construction lives in HCL.

**Tag verification gate.** `release.yml` refuses to publish unless:
- The `version` resolves to a real git tag (`git rev-parse "$VERSION"` succeeds), AND
- That tag points at the same commit as `HEAD`, AND
- The working tree is clean.

This makes `workflow_dispatch` from `main` with a non-existent version fail loud instead of silently producing a `:vX.Y.Z-cu128` image with no matching tag. To dispatch manually, push the tag first and select that tag as the workflow ref.

**Provenance labels.** Every published image carries OCI standard labels populated from the build environment:

| Label | Source |
|---|---|
| `org.opencontainers.image.title` | hard-coded `comfyui-runpod` |
| `org.opencontainers.image.source` / `.url` | hard-coded GitHub repo URL |
| `org.opencontainers.image.licenses` | hard-coded `GPL-3.0-or-later` |
| `org.opencontainers.image.version` | `TAG` env (the git tag for releases, `dev` for dev builds) |
| `org.opencontainers.image.revision` | `GIT_SHA` env (`git rev-parse HEAD` from the build) |
| `org.opencontainers.image.created` | `BUILD_DATE` env (RFC3339 timestamp from the build) |

Inspect with `docker buildx imagetools inspect <image>` or `docker inspect <image> --format '{{json .Config.Labels}}'`. For local builds the provenance labels are empty (intentional — local builds shouldn't claim provenance).

## Public repo conventions

This repo is **public**. Anything committed is visible on GitHub. Therefore:

- **No tokens, no secrets, no private URLs.** Not in code, not in scripts, not in workflow YAML (use `${{ secrets.* }}` references). The model bootstrap reads `HF_TOKEN` from the pod environment but never bakes it.
- **No internal hostnames or coworker handles.** This is a personal-use fork; treat anything beyond `chrisbennight/comfyui-runpod`, `runpod-workers/comfyui-base`, and the upstream model/node repos as out of scope.
- **License is GPL-3.0** (inherited). Don't relicense.

## What "done" looks like for a typical PR

- Lives on a branch. Opened against `main` via a PR — never pushed directly to `main`.
- PR description follows [`.github/pull_request_template.md`](.github/pull_request_template.md): Intent, High-level approach, Design considerations, Flags / concerns / follow-ups, Validation, References. Sections that genuinely don't apply can be marked "n/a" but not deleted.
- Touched files form a coherent change (e.g. add-a-node touches all four files listed above; nothing else).
- `docker buildx bake --print` resolves cleanly with the new args.
- Shell scripts pass `bash -n`.
- README node table and CHANGELOG entry are updated when the user-visible surface moves.
- `docs/context.md` is updated when build args, ports, env vars, paths, or runtime behavior change.
- No commented-out code, no scratch files, no version drift between `docker-bake.hcl` and Dockerfile defaults.
