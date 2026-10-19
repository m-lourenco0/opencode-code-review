# opencode-code-review

Read-only code review agents for [OpenCode](https://opencode.ai) V2.

Two agents work together:

- **`code-reviewer`** — the review lead. Finds the changes to review, reads the surrounding code and project instructions, verifies findings, and reports them by severity with `path:line` references. It can run as your primary agent or be launched by another agent. It never edits files.
- **`review-lens`** — a focused subagent that reviews one angle of a change (`correctness`, `security`, `compatibility/data`, `performance`, or `tests`). The lead fans out to 2–4 lenses for larger or riskier diffs, then verifies and synthesizes their reports.

## Requirements

- OpenCode **V2** (`opencode --version` should show `2.x`)
- `git`
- `bash` — Linux, macOS, or Windows through WSL/Git Bash

## Install

```sh
git clone https://github.com/m-lourenco0/opencode-code-review.git
cd opencode-code-review
./install.sh
```

The installer copies both agents into your global OpenCode agent directory, which is `<config>/agents` (usually `~/.config/opencode/agents`). It asks OpenCode for the exact config path when the CLI is available. Any existing file that differs is backed up as `<name>.bak.<timestamp>`.

Then reload OpenCode and pick the `code-reviewer` agent:

```sh
opencode reload
opencode
```

Or run a review without opening the TUI:

```sh
opencode run --agent code-reviewer "Review the current changes"
```

### Install for one project only

```sh
./install.sh --project                 # current directory -> ./.opencode/agents
./install.sh --project ~/code/my-app   # another repo -> ~/code/my-app/.opencode/agents
```

Project agents override global ones with the same ID and are discovered when OpenCode runs inside that directory tree.

### Symlink instead of copy

```sh
./install.sh --link
```

With symlinks, `git pull` in the clone updates the installed agents immediately. Keep the clone in place; if you move or delete it, the agent symlinks break. Copy mode (the default) is more portable and does not require the clone to stay.

### Update

```sh
git pull
./install.sh
```

The installer is idempotent: identical files are left alone and changed files are backed up.

### Uninstall

```sh
./install.sh --uninstall
./install.sh --uninstall --project ~/code/my-app
```

Only files identical to this repository's agents (or symlinks pointing into it) are removed. Modified files are skipped; add `--force` to remove them anyway.

### All options

| Option | Meaning |
| --- | --- |
| `--global` | Install for the current user (default) |
| `--project [DIR]` | Install into `DIR/.opencode/agents` (defaults to the current directory) |
| `--agents-dir DIR` | Install directly into `DIR` (advanced; `DIR` is the agents directory) |
| `--link` | Symlink instead of copying |
| `--uninstall` | Remove installed agents |
| `--dry-run` | Print actions without changing files |
| `--force` | Replace or remove modified files without a backup/skip |
| `-h`, `--help` | Show help |

## How a review runs

Ask for a review and the lead determines scope from your request:

- Named files, commit, branch, or pull request — exactly that
- Otherwise — working tree and staged changes, falling back to the latest commit or the branch against `main`/`master`

It then reads the full diff, surrounding functions, call sites, and project instructions (`AGENTS.md`, `CLAUDE.md`, `README`, `CONTRIBUTING`). For non-trivial changes it can fan out to `review-lens` subagents, but it re-checks every cited location itself and owns the final report.

Example prompts:

```text
Review the current changes.
Review the changes in src/auth since main.
Review commit 4f2c1ab.
Do a security-focused review of this branch.
```

## What it looks for

Findings are prioritized in this order:

1. **Correctness** — logic errors, null/empty handling, error paths, leaks, broken invariants, data loss
2. **Security** — injection, authorization gaps, unsafe deserialization, path traversal, SSRF, secret exposure
3. **Compatibility and data** — API/contract changes, migrations, serialization, concurrency, idempotency
4. **Tests** — missing coverage, tests that would pass against broken code
5. **Performance** — concrete, evidenced problems only (N+1 queries, unbounded growth, hot paths)
6. **Maintainability** — duplication, dead code, confusing control flow, project-rule violations

The report starts with a verdict (**Approve**, **Approve with comments**, or **Request changes**), lists findings by severity with exact `path:line` locations and failure scenarios, and ends with **Checks run** and **Assumptions / not reviewed**. It does not invent findings when the change looks good.

## Permissions

Both agents are read-only:

- `edit` is denied for every path
- `code-reviewer` may launch only the `review-lens` subagent; `review-lens` may launch no subagents
- Shell is an allowlist: read-only git commands, `ls`/`find`/`rg`/`wc`/`file`, and common test, lint, and typecheck commands (npm, pnpm, bun, pytest, go, cargo, dotnet, make, and others)
- Any other shell command asks for approval; nothing is installed, committed, pushed, or deleted

To widen or narrow the allowlist, edit the `permissions` frontmatter in [`agents/code-reviewer.md`](agents/code-reviewer.md) and [`agents/review-lens.md`](agents/review-lens.md). See the [OpenCode permissions docs](https://opencode.ai/v2/docs/permissions).

### Nested fan-out

`code-reviewer` can be used as a primary agent or as a subagent. If you run it **as a subagent** and still want it to launch `review-lens`, raise OpenCode's subagent depth in your global `opencode.jsonc`:

```jsonc
{
  "experimental": {
    "subagent_depth": 2
  }
}
```

This is not needed when `code-reviewer` is your primary agent.

## Choosing a model

Neither agent pins a model, so `code-reviewer` uses the session's model and `review-lens` inherits the parent's model. To pin one, add frontmatter to the agent file:

```yaml
---
description: ...
mode: all
model: anthropic/claude-sonnet-4-5#high
---
```

Use `provider/model` with an optional `#variant`, as described in the [OpenCode models docs](https://opencode.ai/v2/docs/models).

## Repository layout

```text
agents/code-reviewer.md   review lead (primary or subagent)
agents/review-lens.md     focused lens subagent
install.sh                installer/uninstaller
```

## Contributing

Issues and pull requests are welcome. Keep both agents read-only, preserve the permission allowlist model, and test `./install.sh --dry-run` plus a real install into a temporary directory before opening a PR.

## License

[MIT](LICENSE)
