#!/bin/sh
# Install the current main branch; requires git and a POSIX shell.
(
    set -eu
    command -v git >/dev/null 2>&1 || { echo 'git is required.' >&2; exit 1; }
    app=${NVIM_APPNAME:-nvim}
    case "$app" in .|..|*/*|*\\*) echo 'NVIM_APPNAME must be a directory name.' >&2; exit 1 ;; esac
    target="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}/$app"
    parent=$(dirname "$target")
    mkdir -p "$parent"
    stage=$(mktemp -d "$parent/.nvim-install.XXXXXXXX")
    backup=
    cleanup() {
        code=$?
        trap - EXIT HUP INT TERM
        if [ "$code" -ne 0 ] && [ -n "$backup" ] && [ ! -e "$target" ] && [ ! -L "$target" ]; then
            mv "$backup" "$target" || echo "Restore backup manually: $backup" >&2
        fi
        rm -rf "$stage"
        exit "$code"
    }
    trap cleanup EXIT
    trap 'exit 130' HUP INT TERM
    git clone --depth 1 --single-branch --branch main https://github.com/jay-waves/neovim.git "$stage/config"
    test -f "$stage/config/init.lua"
    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.backup.$(date +%Y%m%d%H%M%S).${stage##*.}"
        mv "$target" "$backup"
        printf 'Backup: %s\n' "$backup"
    fi
    mv "$stage/config" "$target"
    printf 'Installed main: %s\n' "$target"
)
