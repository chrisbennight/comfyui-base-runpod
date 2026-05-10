<!--
PR template — please fill in every section. The goal is for a future reader (or
agent) opening `git log` six months from now to understand not just *what*
changed, but *why* this approach, and what the rejected alternatives were.

Delete the comments and any sections that genuinely don't apply, but don't
delete a section just because it's awkward to fill in — that's usually where
the load-bearing context lives.
-->

## Intent

<!--
What is this PR trying to achieve? State the goal, not the diff. A reader
should be able to tell whether this PR succeeds without reading the code.

Examples:
- "Make the cu130 image bootable on RunPod's RTX 5090 pods."
- "Cut model bootstrap time on a fresh Network Volume from ~30 min to ~10 min."
- "Stop FileBrowser from re-initializing the DB on every pod restart."
-->

## High-level approach

<!--
The shape of the solution in 2-5 sentences. Which files/systems were touched,
and how do they fit together? Skip the line-by-line — this is the mental model
a reviewer needs before reading the diff.
-->

## Design considerations

<!--
What was the interesting decision in this PR, and what alternatives did you
weigh? Include the option(s) you didn't pick and why. Even one paragraph is
fine; the goal is to surface the hidden assumptions.

Useful prompts:
- Did you consider doing this at build time vs runtime?
- Did you consider a smaller diff that would have left some debt?
- Was there a "more correct" approach that was out of scope?
- What constraint forced the chosen direction (RunPod template? size budget?
  upstream node behavior?)
-->

## Flags / concerns / follow-ups

<!--
Anything you're not 100% confident about, anything you noticed but didn't fix,
anything that becomes more important if this PR lands. List them as bullets so
they can be turned into issues.

Examples:
- "The `aria2c` retry logic in download-models.sh assumes HF redirects are
  stable; haven't tested against a 503."
- "Bumping `WANVIDEO_SHA` brought in a node that requires `triton`. Works on
  cu128 but I haven't verified cu130 yet — flagging for review."
- "Follow-up: add an OCI label for the ComfyUI version so users can `docker
  inspect` to see what's baked."
-->

## Validation

<!--
What did you actually run to convince yourself this works? Be specific.

- [ ] `docker buildx bake --print -f docker-bake.hcl cu128 cu130 dev`
- [ ] `bash -n start.sh scripts/*.sh`
- [ ] Triggered the `Dev Build` workflow and pulled `:dev-cu128` on a RunPod pod
- [ ] Manually verified ComfyUI loads with `--listen 0.0.0.0` and the new node imports
- [ ] (other)
-->

## References

<!--
Links and external context. Anything a reviewer might need to follow along, or
that future-you will want when revisiting:

- Upstream PRs / issues / commits
- Hugging Face model cards
- ComfyUI / RunPod docs
- Discussion threads, RFCs, related PRs in this repo
-->
