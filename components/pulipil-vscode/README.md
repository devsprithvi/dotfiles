# pulipil for VS Code

> **Status: under active development — parked, pre-release.** No stable or beta
> release exists yet, and it is not published to any marketplace.

A VS Code extension that provides **real-time, provider-aware completion** for
`pulipil.cue` package manifests. It is a thin Language Server Protocol client:
all the intelligence lives in the `pulipil` binary's language server
(`pulipil lsp --stdio`), so the editor experience always matches the CLI.

This is a separate component from the `pulipil` engine itself. The engine
(Go) lives in `../pulipil`; this extension (TypeScript) only launches and talks
to it.

## What you get

As you type a package `name` in a manifest, the server resolves which provider
governs that entry (from the enclosing object's `provider:` pin, or the default
order) and pulls live candidates from that ecosystem's registry:

| Provider (`provider:`) | Source                | Completion style        |
| ---------------------- | --------------------- | ----------------------- |
| `npm`                  | registry.npmjs.org    | prefix search           |
| `crates`               | crates.io             | prefix search           |
| `pypi`                 | pypi.org              | exact-name lookup       |
| `brew`                 | formulae.brew.sh      | exact-name lookup       |

Each registry has its own request and response shape; the server normalizes
them into `name` / `version` / `description` completion items.

```cue
packages: [
    // Typing here queries crates.io in real time.
    {name: "ser", provider: "crates"},

    // No provider pin → the default source order is tried.
    {name: "left"},
]
```

## Requirements

- The `pulipil` binary on your `PATH` (or set `pulipil.server.path`).
  Build it from `../pulipil`:

  ```sh
  cd ../pulipil && go build -o pulipil ./cmd/pulipil
  ```

## Settings

| Setting                | Default              | Description                                   |
| ---------------------- | -------------------- | --------------------------------------------- |
| `pulipil.server.path`  | `pulipil`            | Path to the `pulipil` binary.                 |
| `pulipil.server.args`  | `["lsp","--stdio"]`  | Arguments used to launch the server.          |
| `pulipil.trace.server` | `off`                | Trace JSON-RPC traffic for debugging.         |

## Commands

- **pulipil: Restart Language Server** — restarts the server process.

## Developing

```sh
npm install
npm run compile      # or: npm run watch
```

Then press <kbd>F5</kbd> in VS Code to launch an Extension Development Host.
Open a `pulipil.cue` file and start typing a package `name` to see completions.

## Architecture

```
VS Code  ──stdio JSON-RPC──▶  pulipil lsp --stdio
(this extension)                    │
                                    ├─ resolves provider from the manifest
                                    └─ queries the registry live (npm/crates/…)
```

The extension is intentionally minimal. Adding a new ecosystem is a change in
the Go server (a new `remote.Source`), not here.
