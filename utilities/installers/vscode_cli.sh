#!/usr/bin/env bash
# ── Installer Module: VS Code CLI (standalone, for tunnels) ─────────────────

install_vscode_cli() {
    local dest="$HOME/.local/bin/code" vs_arch tmp
    [ -x "$dest" ] && return 0

    case "$(uname -m)" in
        aarch64|arm64) vs_arch="arm64" ;;
        x86_64)        vs_arch="x64"   ;;
        *) echo "[vscode] unsupported arch" && return 1 ;;
    esac

    mkdir -p "$HOME/.local/bin"
    tmp="$(mktemp -d)"
    curl -fsSL "https://update.code.visualstudio.com/latest/cli-linux-${vs_arch}/stable" -o "${tmp}/code.tgz"
    tar -xf "${tmp}/code.tgz" -C "$tmp"
    mv "${tmp}/code" "$dest" && chmod +x "$dest"
    rm -rf "$tmp"
    echo "[vscode] CLI installed -> $dest"
}
