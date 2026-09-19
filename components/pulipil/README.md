# pulipil

A configuration-driven package installer engine, written in Go.

You describe the packages you want in a [CUE](https://cuelang.org) file, and
`pulipil` installs them through pluggable **package providers** (dnf, apt,
pacman, apk, zypper, brew, scoop, winget, ...). Custom providers can be
declared directly in configuration, so teaching `pulipil` about a new package
source never requires recompiling.

The engine is a small **interpreter**: beyond declaring packages, you can
declare **commands** to run. It executes only what you declare, in order,
honouring platform guards and dependencies between steps (for example, "run
this only after `git` is installed"), and stops cleanly on the first failure.

> **Status: under active development — parked, pre-release.** No stable or beta
> release exists yet, and this is not wired into the parent dotfiles bootstrap.
> The engine, providers, config validation, CLI and language server are
> functional and covered by tests, but interfaces may still change. The VS Code
> client lives in the sibling `pulipil-vscode` component.

## Philosophy

- **Configuration, not scripting.** One typed, validated CUE document describes
  desired state. No YAML-with-logic, no per-distro shell branches.
- **Providers are data.** Built-in providers are declarative command tables.
  Custom providers use the exact same shape — nothing is special about the
  built-ins.
- **Honest and idempotent.** `plan` shows what will change; `install` only acts
  on the difference and relies on provider checks + package-manager idempotency.
- **Interpret, don't improvise.** Commands run only when declared, only in the
  order declared, and only when their dependencies and platform guards are met.
  The orchestrator (chezmoi) decides *when* to invoke pulipil; pulipil decides
  *what* runs.

## Install / build

Requires Go 1.24+.

```bash
make build        # builds ./bin/pulipil
make install      # installs to $GOBIN
```

## Usage

```bash
pulipil schema                      # print the CUE config schema
pulipil validate -c config.cue      # validate a config
pulipil providers                   # list providers and availability
pulipil plan     -c config.cue      # preview package + command changes
pulipil install  -c config.cue      # install packages, then run commands
pulipil install  -c config.cue -y   # apply without prompting
pulipil run      -c config.cue      # run declared command steps only
pulipil run build -c config.cue     # run a single named step
pulipil search ripgrep -p crates    # live registry search (LSP completion path)
pulipil lsp --info                  # language-server capabilities
pulipil lsp --stdio                 # run the language server for an editor
```

## Language server & real-time completion

`pulipil lsp --stdio` starts a Language Server Protocol server over JSON-RPC on
stdio. As you edit a package `name` in a manifest, it resolves the governing
provider from the enclosing object (its `provider:` pin, else the default
order) and pulls candidates **live from that ecosystem's registry**:

| `provider:` | Source             | Style             |
| ----------- | ------------------ | ----------------- |
| `npm`       | registry.npmjs.org | prefix search     |
| `crates`    | crates.io          | prefix search     |
| `pypi`      | pypi.org           | exact-name lookup |
| `brew`      | formulae.brew.sh   | exact-name lookup |

Each registry speaks its own wire format, so each source (`internal/remote`)
owns its own request and response shape and normalizes results into
`name` / `version` / `description`. When no internet source matches a provider,
the server falls back to the installed package manager's own `search`.

Editors launch the server over stdio. The VS Code client is the
`pulipil-vscode` component next to this one.

If `-c` is omitted, `pulipil` auto-discovers `pulipil.cue`, `.pulipil.cue`, or
`config.cue` in the current directory.

## Configuration

See [`examples/packages.cue`](examples/packages.cue) and `pulipil schema`.

```cue
defaults: providers: ["dnf", "apt", "brew"]

packages: [
	{name: "git"},
	{name: "ripgrep", provider: "dnf"},
	{name: "zsh", when: os: ["linux"]},
]
```

### Custom providers

```cue
providers: pipx: {
	binary:  "pipx"
	install: ["pipx", "install", "{{.Name}}{{if .Version}}=={{.Version}}{{end}}"]
	remove:  ["pipx", "uninstall", "{{.Name}}"]
	check:   ["pipx", "list", "--short"]
	search:  ["pipx", "search", "{{.Query}}"]
}
```

Command elements are Go `text/template` strings evaluated per invocation with
`.Name`, `.Version`, `.Query`, and `.Args`. An element that renders empty is
dropped, which makes conditional arguments trivial.

### Commands (the interpreter)

Declare steps to run after packages. Each step is deterministic and guarded:

```cue
commands: [
	// Runs only after the `git` package is present.
	{name: "clone", run: ["git", "clone", "https://example.com/x", "/tmp/x"], needs: ["git"]},

	// Depends on the previous step; `shell: true` enables pipes/redirection.
	{name: "build", run: ["make", "-C", "/tmp/x"], needs: ["clone"], trigger: "onchange"},
]
```

Step fields:

- `run` (required) — argv to execute; runs directly unless `shell: true`.
- `needs` — names that must be satisfied first: a declared package (present and
  platform-matched) or an **earlier** command that was not skipped. Unmet
  dependencies **skip** the step (they do not fail it).
- `when` — platform guard (`os` / `arch`), same as packages.
- `requiresRoot`, `env`, `dir` — elevate, add env vars, set the working dir.
- `trigger` — advisory metadata (`once` | `onchange` | `always`) for the
  orchestrator; see below.

Rules: steps run in declared order, a `needs` reference may only point at an
earlier step, and a step that runs and exits non-zero fails the run (unless
`--keep-going`). `pulipil plan` shows exactly which steps will run or skip and
why.

### Orchestration with chezmoi

Today the parent dotfiles repo uses [chezmoi](https://www.chezmoi.io/). Its
`run_once_` / `run_onchange_` script prefixes decide *when* to invoke pulipil;
pulipil's `trigger` metadata documents the intent per step. A chezmoi script
can simply call `pulipil install` (packages + commands) or `pulipil run`
(commands only), and chezmoi handles the "only once" / "on change" gating:

```bash
# .chezmoiscripts/run_onchange_pulipil.sh.tmpl
pulipil install -c "{{ .chezmoi.sourceDir }}/pulipil.cue" -y
```

## Layout

```
cmd/pulipil/            CLI entrypoint
internal/cli/           cobra commands + UI wiring
internal/config/        CUE schema (embedded) + loader/validator
internal/provider/      Provider interface, registry, command provider, runner
internal/provider/builtin/  built-in provider tables
internal/engine/        plan + apply for packages and command steps
internal/lsp/           LSP server: transport, protocol, handler, resolver
internal/remote/        internet-backed completion sources (npm/crates/pypi/brew)
internal/ui/            lipgloss-based terminal output
examples/               sample configuration
```

The VS Code client is a separate component: `../pulipil-vscode`.

## Roadmap

- Secret injection for private repositories (schema hook already present).
- Schema-aware LSP diagnostics + hover using the embedded `#Config`.
- Provider result caching for faster completion.
- Parallel installs with dependency ordering.
