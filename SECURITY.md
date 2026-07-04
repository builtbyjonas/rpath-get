# Security Policy

## Supported Versions

Security fixes target the latest deployed version of `get.rpath.dev` and the latest released version of `rpath`.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately to:

```text
me@byjonas.dev
```

Do not open a public issue for vulnerabilities involving shell injection, installer tampering, checksum bypasses, PATH hijacking, unsafe file deletion, or unsafe environment mutation.

Please include:

- Affected script or route
- Affected operating system and shell
- Reproduction steps
- Expected and actual behavior
- Whether the issue requires local access

## Security Principles

- Serve only reviewed installer and uninstaller scripts.
- Verify GitHub Release checksums before installing binaries.
- Install user-local files by default.
- Ask before shell wrapper installation unless explicitly configured.
- Keep normal `rpath` refresh behavior separate from networked install and upgrade flows.
