# Security Policy

Orbit is a GPU terminal. It owns a PTY, the clipboard, `~/.config/orbit`, and a plugin loader that can type into the shell. A real vulnerability here is not a cosmetic bug — it can run commands as the logged-in user.

> [!WARNING]
> **Do not file a public GitHub issue, discussion, or pull request with exploit details.**
> Use [private vulnerability reporting](https://github.com/marksikaundi/Orbit/security/advisories/new).

---

## Supported versions

Security patches ship on the current `2.x` line only. Build from a tagged release on [GitHub Releases](https://github.com/marksikaundi/Orbit/releases), not an unreviewed fork.

| Version | Status | Security updates |
| :------ | :----- | :--------------- |
| **2.x** | Current (`VERSION` / `v2.*` tags) | :white_check_mark: Yes |
| 1.x     | Retired | :x: No |
| &lt; 1.0 | Pre-release | :x: No |

Nightly / untagged `2026-live` commits may contain fixes before they are tagged. They are not a supported channel.

---

## Report a vulnerability

**Use this form:** [Open a private GitHub advisory](https://github.com/marksikaundi/Orbit/security/advisories/new)

That report is visible only to maintainers until we publish an advisory. If the form is disabled, contact [@marksikaundi](https://github.com/marksikaundi) on GitHub **without** attaching a full exploit in a public comment.

### What to send

A report we can act on includes:

| Field | Why it matters |
| ----- | -------------- |
| Affected build | Version, git tag (`v2.1.1`), or commit SHA — plus OS |
| Impact | What an attacker gains (code exec, secret leak, unexpected file write, …) |
| Preconditions | Local only? Needs a malicious plugin? Needs a hostile OSC sequence in the PTY? |
| Reproduction | Minimal steps or a proof of concept |
| Evidence | Logs, screenshots, payload (redact secrets) |
| Fix | Patch or mitigation, if you have one |

Reports without a reproduction still help — send them. Vague “this looks unsafe” notes with no steps take longer.

### Please do not

- Open a public issue titled “security” with a working exploit
- Attach live credentials, private keys, or production tokens
- Demand a CVE number before we have confirmed the bug
- Disclose the issue publicly until we have shipped a fix or agreed a date with you

---

## What happens after you report

We follow **coordinated disclosure**. There is no bug bounty.

| Step | Target |
| ---- | ------ |
| Acknowledgment | Within **7 days** |
| Triage (valid / invalid / duplicate) | Within **14 days** of acknowledgment |
| Fix on supported `2.x` | As soon as practical; Critical first |
| Public advisory | After a patched release, or on an agreed date |

1. We reproduce and classify severity.
2. We patch on a private branch when the issue is exploitable in the wild.
3. We tag a `2.x` release and, when appropriate, publish a [GitHub Security Advisory](https://github.com/marksikaundi/Orbit/security/advisories) with credit to the reporter (unless you ask otherwise).
4. We may request a CVE through GitHub for confirmed, in-scope issues.

If we miss a date, we will still update you on the advisory thread rather than going silent.

---

## Severity

We classify confirmed issues using the same scale as `zig build security-scan`:

| Severity | Meaning | Example |
| -------- | ------- | ------- |
| **Critical** | Unintended command execution or equivalent, with little or no extra user action | Plugin / OSC / paste path that runs a shell payload the user did not intend |
| **High** | Secrets leave Orbit, or Orbit writes/executes outside its expected paths | Config, clipboard, logs, or plugins leaking tokens; path escape from the plugins dir |
| **Warning** | Security-relevant but not directly exploitable alone | Dangerous `insert` payload that is warned on but still runnable |
| **Info** | Hardening / defense-in-depth | Missing check that does not currently yield a practical attack |

We may also record a CVSS score on a published advisory. Severity is about **Orbit’s code and default trust boundaries**, not about a shell command the user typed themselves.

---

## Threat model

Orbit runs **as the user**. It is not a sandbox. The interactive shell is supposed to run commands. That is not a vulnerability.

The security boundary is everything **Orbit itself** does *without* an explicit, informed user action in the shell.

```text
  hostile input ──► Orbit (parser, UI, plugins, clipboard)
                         │
                         ├── PTY / ConPTY  ──► user shell
                         ├── ~/.config/orbit/
                         └── host APIs (clipboard, files, window)
```

### In scope

| Area | We want reports for |
| ---- | ------------------- |
| PTY / ConPTY | Escape from intended I/O; injecting commands the user did not run |
| ANSI / OSC / DCS | Sequences that execute, overwrite files, or leak data without consent |
| Paste / clipboard | Bracketed-paste bypass, unescaped paste that becomes typed commands |
| Plugins | Path traversal out of `~/.config/orbit/plugins/`; `insert` payloads that execute on **load** (not on explicit command) |
| Config | Unexpected file read/write outside `~/.config/orbit` |
| Secrets | Keys or tokens embedded in source, scripts, CI, or written to logs |
| Releases / CI | Tampered artifacts, poisoned workflows, or a compromised `orbit` binary story tied to this repo |

### Out of scope

| Not a vulnerability | Why |
| ------------------- | --- |
| A command the user ran in the shell | Orbit is a terminal |
| A plugin the user installed whose `insert` payload runs `git`, `curl`, etc. **when they invoke it** | Plugins are user-controlled shell snippets; they are audited and warned, not blocked |
| “Please sandbox every command” | Out of product scope |
| Crash / hang that needs local cooperation and does not escalate | Reliability bug — use a public issue |
| Dependency issue with no Orbit-specific trigger | Report it upstream; mention us if we need a bump |
| Social engineering, phishing pages that are not Orbit | Not our code |
| Already-compromised machine / malicious `PATH` wrapping `orbit` | Attacker already has the user |

If you are unsure, report privately. We would rather close a duplicate than miss a real bug.

---

## Plugin trust

Plugins live in `~/.config/orbit/plugins/<name>/` (`plugin.toml` plus optional scripts). An `insert` action types `payload` into the focused PTY — the same as the user typing. A `[tool]` `run` action executes **your** command/script when you invoke it (never on load).

- Treat third-party plugin folders like shell scripts you did not write.
- Orbit **audits** insert payloads (`curl … \| sh`, `rm -rf /`, reverse shells, `sudo`, …) and warns at load and at run. Warnings are not a sandbox.
- Plugin scripts must stay under the plugins directory (`..` is refused).
- Plugins that resolve outside the plugins directory are skipped.
- Bundled pack under `assets/plugins/` is reviewed in this repo. Anything else is your trust decision.

See [assets/plugins/README.md](../assets/plugins/README.md).

---

## Hardening (operators)

| Practice | Detail |
| -------- | ------ |
| Install from source you control | Clone [marksikaundi/Orbit](https://github.com/marksikaundi/Orbit), check out a `v*` tag, `zig build -Doptimize=ReleaseFast` |
| Do not run untrusted plugin trees | Only copy plugin folders you have read |
| Keep config private | `~/.config/orbit/` can contain workspace paths and plugin payloads |
| Prefer tagged releases | [Releases](https://github.com/marksikaundi/Orbit/releases) over random branches |
| Run the scanner in forks / PRs | `zig build security-scan` (CI already fails on HIGH/CRITICAL) |

```bash
zig build security-scan
zig build security-scan -- --fail-on warning   # stricter local bar
```

The scanner walks `src/`, `scripts/`, and plugins for hardcoded secrets and injection heuristics. It does **not** prove the binary is safe. Private reports still matter.

---

## Safe harbor

If you:

- Report in good faith through the private advisory form
- Avoid privacy violations, service disruption, and data destruction beyond what is needed to demonstrate the bug
- Give us time to patch before public disclosure

…we will not pursue legal action related to that research against you. This is not permission to attack users, infrastructure you do not own, or accounts that are not yours.

---

## Contact

| Channel | Use for |
| ------- | ------- |
| [Private advisory](https://github.com/marksikaundi/Orbit/security/advisories/new) | Vulnerabilities (preferred) |
| [GitHub issues](https://github.com/marksikaundi/Orbit/issues) | Ordinary bugs, crashes, UX |
| [CONTRIBUTING.md](../CONTRIBUTING.md#security) | How to run scans as a contributor |

Maintainer: [Mark Sikaundi](https://github.com/marksikaundi) · License: [Apache-2.0](../LICENSE)
