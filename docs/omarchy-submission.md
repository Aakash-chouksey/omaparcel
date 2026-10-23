# Omarchy marketplace submission

This is the exact path to list Omatunnel at
[plugins.omarchy.org](https://plugins.omarchy.org/). The submission is omacom/omarchy-plugin-marketplace#12689.

## Before submitting

- The repository is public and has a root `manifest.json` (version 1.1.2) whose
  entry point exists.
- The root `README.md` has installation and removal instructions.
- The root `LICENSE` is MIT.
- The root `preview.png` is the 1600x900 listing image. It shows the panel and
  the friend page. The marketplace optimizes it.
- The display name is `Omatunnel`. The permanent plugin ID is
  `codejack.tunnelshare`. It is outside the reserved `omarchy.*` namespace and
  is the ID used by the local install.
- Omatunnel needs the TunnelShare daemon and `tsctl`. This is in the manifest
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
  --title "[Plugin]: Omatunnel" \
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
- Omatunnel runs unsandboxed. The marketplace listing is not a security audit.
