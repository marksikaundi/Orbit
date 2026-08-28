# Security Policy

Orbit is a terminal emulator. Security reports matter: a bug here can affect the shell, plugins, clipboard, and whatever runs inside a workspace.

Please report vulnerabilities **privately**. Do not open a public GitHub issue, discussion, or pull request with exploit details.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 2.x     | Yes (current) |
| 1.x     | No |
| < 1.0   | No |

Security fixes land on the current `2.x` release line. Older versions do not receive patches.

## Reporting a vulnerability

**Preferred:** [GitHub private vulnerability reporting](https://github.com/marksikaundi/Orbit/security/advisories/new)

If that form is unavailable, contact the maintainer privately through GitHub (do not include a full exploit in a public issue).

Include as much of the following as you can:

- Affected version, tag, or commit SHA
- Description of the issue and why it is security-sensitive
- Steps to reproduce or a proof of concept
- Relevant logs, payloads, or screenshots
- Potential impact
- Suggested mitigations or a fix, if you have one

You can expect an acknowledgment within **7 days**. After that we will assess the report, work on a fix when confirmed, and coordinate public disclosure with you.

Please give us reasonable time to ship a fix before discussing the issue publicly.

## In scope

Examples of reports we want:

- Arbitrary command execution outside the user’s intended shell
- Privilege escalation or sandbox/PTY escape
- Secrets leaked from config, logs, clipboard, or plugins
- Unsafe plugin `insert` / shell-injection paths
- Path traversal or unexpected file writes from Orbit itself
- Supply-chain issues in release artifacts or CI

## Out of scope

- Bugs that only affect an already-compromised machine
- User-installed plugins that intentionally run commands (Orbit is a terminal)
- Denial of service that requires local, unprivileged cooperation
- Issues in third-party dependencies with no Orbit-specific impact (report those upstream)

## After a report is confirmed

1. We investigate and, if valid, prepare a fix on a private branch when needed.
2. We ship a patched release on the supported `2.x` line.
3. We may publish a [GitHub Security Advisory](https://github.com/marksikaundi/Orbit/security/advisories) once the fix is available.

## Automated checks

Orbit scans `src/`, `scripts/`, and plugins for hardcoded secrets and injection patterns. CI runs this on every push and pull request.

```bash
zig build security-scan
```

Risky plugin inserts also warn at load time and when executed. These checks do **not** replace private reporting of real vulnerabilities.

See [CONTRIBUTING.md](../CONTRIBUTING.md#security) for how contributors should run the scanner locally.
