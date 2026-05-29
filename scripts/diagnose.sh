#!/usr/bin/env bash
# ── Diagnostic: Run this in your Codespace terminal ──────────────────────
# Usage: bash scripts/diagnose.sh

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Dotfiles PATH Diagnostic           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. Find where binaries actually live on disk
echo "=== 1. BINARY LOCATIONS ON DISK ==="
for tool in chezmoi agy sheldon starship; do
    locations=$(find /usr /home "$HOME" -name "$tool" -type f 2>/dev/null | head -5)
    if [[ -n "$locations" ]]; then
        echo "  $tool found at:"
        echo "$locations" | sed 's/^/    /'
    else
        echo "  $tool: NOT INSTALLED ANYWHERE"
    fi
done

# 2. What's in ~/.local/bin?
echo ""
echo "=== 2. ~/.local/bin CONTENTS ==="
if [[ -d "$HOME/.local/bin" ]]; then
    ls -la "$HOME/.local/bin/" 2>/dev/null
else
    echo "  DIRECTORY DOES NOT EXIST: $HOME/.local/bin"
fi

# 3. Is ~/.local/bin in PATH?
echo ""
echo "=== 3. FULL PATH (one per line) ==="
echo "$PATH" | tr ':' '\n' | nl

echo ""
echo "=== 4. Is ~/.local/bin in PATH? ==="
if echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    echo "  YES — ~/.local/bin is in PATH"
else
    echo "  NO — ~/.local/bin is NOT in PATH ← THIS IS THE PROBLEM"
fi

# 4. Can the shell find them via command -v?
echo ""
echo "=== 5. COMMAND LOOKUP (command -v) ==="
for tool in chezmoi agy sheldon starship; do
    loc=$(command -v "$tool" 2>/dev/null)
    if [[ -n "$loc" ]]; then
        echo "  $tool → $loc"
    else
        echo "  $tool → NOT FOUND on PATH"
    fi
done

# 5. Environment info
echo ""
echo "=== 6. ENVIRONMENT ==="
echo "  SHELL=$SHELL"
echo "  USER=$(whoami)"
echo "  HOME=$HOME"
echo "  Current shell: $(ps -p $$ -o comm= 2>/dev/null || echo unknown)"
cat /etc/os-release 2>/dev/null | head -3 | sed 's/^/  /'

# 6. Check what profile files exist and if they add ~/.local/bin
echo ""
echo "=== 7. PROFILE FILES THAT SET PATH ==="
for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc" "$HOME/.zprofile" "/etc/profile" "/etc/bash.bashrc"; do
    if [[ -f "$f" ]]; then
        match=$(grep -n 'local/bin\|\.local' "$f" 2>/dev/null)
        if [[ -n "$match" ]]; then
            echo "  $f → HAS local/bin reference:"
            echo "$match" | sed 's/^/    /'
        else
            echo "  $f → exists but NO local/bin reference"
        fi
    fi
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Diagnostic complete                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
