# get.rpath.dev

Hosted installer and uninstaller script server for `rpath`.

This service serves the canonical scripts used by:

```powershell
irm https://get.rpath.dev/install.ps1 | iex
irm https://get.rpath.dev/uninstall.ps1 | iex
```

```sh
curl -fsSL https://get.rpath.dev/install.sh | sh
curl -fsSL https://get.rpath.dev/uninstall.sh | sh
```

## Routes

| Route            | Purpose                        |
| ---------------- | ------------------------------ |
| `/install.sh`    | Linux/macOS installer          |
| `/install.ps1`   | Windows PowerShell installer   |
| `/uninstall.sh`  | Linux/macOS uninstaller        |
| `/uninstall.ps1` | Windows PowerShell uninstaller |
| `/healthz`       | JSON health check              |

Unknown routes return plain text `404` responses. Script responses use short CDN caching and are served directly from `scripts/`.

## Development

```sh
bun install
bun run check
bun run dev
```

The local server defaults to `http://localhost:3000`.

## Deployment

This repository is intended to deploy as a standalone Vercel project for `get.rpath.dev`.

`src/index.js` is the Express entrypoint Vercel detects. `vercel.json` keeps the project on the generic framework preset, applies script response headers, and rewrites incoming paths to the Express app.

## Release Safety

The scripts install only user-local files by default, verify GitHub Release checksums before replacing binaries, and ask before installing shell wrappers unless configured otherwise.
