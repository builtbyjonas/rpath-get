# Contributing

Thanks for helping improve `get.rpath.dev`.

## Setup

```sh
bun install
bun run check
```

For script changes, also run:

```sh
sh -n scripts/install.sh
sh -n scripts/uninstall.sh
pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts/install.ps1)) | Out-Null"
pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts/uninstall.ps1)) | Out-Null"
```

## Pull Requests

- Keep installer and uninstaller behavior user-scoped by default.
- Verify downloaded release artifacts before installing them.
- Keep script output clear, actionable, and safe for pipe-to-shell usage.
- Update `README.md` when routes, flags, or deployment behavior changes.
- Add or update issue templates if new support categories appear.

## Commit Messages

Use short, imperative summaries, for example:

```text
Add installer dry-run output
Document Vercel deployment
Fix Windows PATH removal
```
