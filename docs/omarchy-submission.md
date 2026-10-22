# Omarchy marketplace submission

This is the exact path to list TunnelShare at
[plugins.omarchy.org](https://plugins.omarchy.org/). The submission is prepared
but not submitted.

## Before submitting

- The repository is public and has a root `manifest.json` (version 1.0.0) whose
  entry point exists.
- The root `README.md` has installation and removal instructions.
- The root `LICENSE` is MIT.
- The root `preview.png` is the panel screenshot. The marketplace optimizes it.
- The plugin ID is `codejack.tunnelshare`. It is outside the reserved
  `omarchy.*` namespace and is the ID used by the local install.
- The plugin needs the TunnelShare daemon and `tsctl`. This is in the manifest
  description, the README, and the maintainer notes.

## Category and tags

- Category: `Productivity`
- Tags: `bar, quickshell, system`

## Submit

The exact issue body is in
[`docs/omarchy-submission-body.md`](omarchy-submission-body.md). Review every
checklist item, then create the issue:

```bash
gh issue create \
  --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: TunnelShare" \
  --body-file docs/omarchy-submission-body.md
```

The marketplace applies the `submission` label and starts automated validation
and the security baseline against the current commit. A maintainer then makes
the publication decision. Do not submit until the repository is pushed and the
commit is final.

## After approval

- The listing install command is `omarchy plugin add <repo-url>`.
- Updates use the "Plugin verification" issue form with the existing plugin ID,
  the repo URL, and the full 40-character commit SHA.
- The marketplace clones mutable upstream HEAD. Users must inspect the installed
  commit before enabling.
- The plugin runs unsandboxed. The marketplace listing is not a security audit.
