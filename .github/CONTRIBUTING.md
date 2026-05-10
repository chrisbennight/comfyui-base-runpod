# Contributing

Thanks for your interest. This repo builds a slim ComfyUI container for use on RunPod, published to GitHub Container Registry as `ghcr.io/chrisbennight/comfyui-runpod`.

## Releases

Releases are driven by tags. The `Release` workflow builds and pushes both CUDA variants to GHCR using the repo's `GITHUB_TOKEN` — no Docker Hub secrets required.

To cut a release:

1. Pick a semver tag, e.g. `v0.2.0`.
2. Trigger the workflow in any of three ways:
   - Push the tag: `git tag v0.2.0 && git push origin v0.2.0`
   - Publish a GitHub Release with that tag.
   - Run the **Release** workflow manually with `version = v0.2.0`.
3. The workflow builds and pushes:
   - `ghcr.io/chrisbennight/comfyui-runpod:v0.2.0-cu128`
   - `ghcr.io/chrisbennight/comfyui-runpod:cu128`
   - `ghcr.io/chrisbennight/comfyui-runpod:latest`
   - `ghcr.io/chrisbennight/comfyui-runpod:v0.2.0-cu130`
   - `ghcr.io/chrisbennight/comfyui-runpod:cu130`

Tags are defined in `docker-bake.hcl`; do not override via `--set` in the workflow.

## Dev builds

Use the **Dev Build** workflow (manually triggered). It pushes `ghcr.io/chrisbennight/comfyui-runpod:dev-cu128` and `:dev-cu130` without touching `:latest`.

For local builds:

```bash
docker buildx bake -f docker-bake.hcl dev
```

## Bumping pinned versions

- ComfyUI core, custom node SHAs, PyTorch, CUDA suffix — all live in `docker-bake.hcl` as `variable` blocks.
- To refresh custom-node SHAs to upstream HEAD:
  ```bash
  GITHUB_TOKEN=<gh_pat> ./scripts/fetch-hashes.sh
  ```
  Paste the output blocks back into `docker-bake.hcl`.

## PRs

- Keep changes focused and explain the rationale in the description.
- Update `docs/context.md` when changing build args, ports, env vars, or runtime behavior.
- If you add or remove a custom node, update `scripts/fetch-hashes.sh`, the Dockerfile, `docker-bake.hcl`, and the README node table together.

## License

GPL-3.0 (inherited from upstream). By contributing you agree your changes ship under GPL-3.0.
