#!/usr/bin/env bash
# Reverse what install.sh did, and nothing else.
#
# Usage: ./uninstall.sh [--dry-run] [--tools]
#
#   --dry-run   print what would happen, change nothing
#   --tools     also print the commands that remove the programs install.sh
#               installed (printed, never run: other things may rely on them)
#
# Removes the ~/.zshrc block, the symlinks that point into this repo, and the
# wt-review cache, then puts back anything install.sh had moved out of the way.
# Programs and zellij's saved sessions are left in place. Safe to re-run.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib.sh
source "$REPO/lib.sh"

SHOW_TOOLS=0
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=1 ;;
        --tools) SHOW_TOOLS=1 ;;
        -h | --help)
            sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p;}' "$0"
            exit 0
            ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

((DRY_RUN)) && note "dry run: nothing will be changed"

# --- ~/.zshrc -------------------------------------------------------------------

# Drops the marked block, plus the one blank line install.sh put in front of it,
# so an install/uninstall round trip leaves the file byte-for-byte as it was.
strip_block() {
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b        { skip = 1; held = 0; next }
        skip && $0 == e { skip = 0; next }
        skip           { next }
        held           { print ""; held = 0 }
        $0 == ""       { held = 1; next }
                       { print }
        END            { if (held) print "" }
    ' "$1"
}

remove_zshrc_block() {
    local file=$1 tmp
    [[ -f $file ]] || return 0
    if ! grep -Fxq -- "$MARK_BEGIN" "$file"; then
        ok "$(tilde "$file") has no workflow block"
        return 0
    fi
    if ! grep -Fxq -- "$MARK_END" "$file"; then
        warn "$(tilde "$file") has the opening marker but not the closing one; edit it by hand"
        return 0
    fi
    step "removing the workflow block from $(tilde "$file")"
    if ((DRY_RUN)); then
        would "delete lines from '$MARK_BEGIN' to '$MARK_END'"
        return 0
    fi
    tmp=$(mktemp)
    strip_block "$file" >"$tmp"
    # Write through rather than rename, so a ~/.zshrc that is itself a symlink
    # (into a dotfiles repo, say) stays one and keeps its permissions.
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

headline "Shell"
{
    echo "$HOME/.zshrc"
    manifest_list zshrc
} | sort -u | while IFS= read -r f; do
    remove_zshrc_block "$f"
done

# --- links ----------------------------------------------------------------------

# Everything install.sh links, whether or not the manifest survived.
known_links() {
    echo "$CONFIG_HOME/zellij"
    echo "$WORKFLOW_LINK"
    local f
    for f in "$REPO"/bin/*; do
        [[ -f $f ]] && echo "$BIN_DIR/$(basename "$f")"
    done
    manifest_list link
}

remove_link() {
    local dest=$1 target
    if [[ ! -L $dest ]]; then
        [[ -e $dest ]] && note "$(tilde "$dest") is not a symlink; left alone"
        return 0
    fi
    target=$(readlink "$dest")
    # Ours if it points into this repo, or if we recorded it and it now dangles
    # (the repo moved). Anything else was put there by someone else.
    if [[ $target == "$REPO"/* ]] || { manifest_has link "$dest" && [[ ! -e $dest ]]; }; then
        step "removing $(tilde "$dest")"
        run rm "$dest"
    else
        note "$(tilde "$dest") points to $target, not this repo; left alone"
    fi
}

headline "Links"
known_links | sort -u | while IFS= read -r dest; do
    remove_link "$dest"
done
if [[ -d $(dirname "$WORKFLOW_LINK") ]]; then
    run rmdir "$(dirname "$WORKFLOW_LINK")" 2>/dev/null || true
fi

# --- backups --------------------------------------------------------------------

# Newest first, so when something was backed up more than once the most recent
# copy is the one restored. Older copies stay where they are.
headline "Backups"
restored=""
found_backup=0
while IFS=$'\t' read -r original backup; do
    [[ -n $original ]] || continue
    found_backup=1
    if [[ ! -e $backup && ! -L $backup ]]; then
        continue
    fi
    case $'\n'"$restored" in
        *$'\n'"$original"$'\n'*)
            note "older backup kept at $(tilde "$backup")"
            continue
            ;;
    esac
    # Under --dry-run the link is still in place; it would be gone by now for real.
    if [[ -e $original || -L $original ]] && ! ((DRY_RUN)); then
        warn "$(tilde "$original") exists again; backup kept at $(tilde "$backup")"
        continue
    fi
    step "restoring $(tilde "$original")"
    run mv "$backup" "$original"
    restored+="$original"$'\n'
done < <(manifest_list backup | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }')
((found_backup)) || ok "nothing was backed up"

# --- leftovers ------------------------------------------------------------------

headline "Cleanup"
cache=${XDG_CACHE_HOME:-$HOME/.cache}/wt-review
if [[ -d $cache && $cache == */wt-review ]]; then
    step "removing $(tilde "$cache")"
    run rm -rf "$cache"
fi

tools=$(manifest_list tool)

if [[ -d $STATE_DIR ]]; then
    step "removing $(tilde "$STATE_DIR")"
    run rm -f "$MANIFEST"
    run rmdir "$STATE_DIR" 2>/dev/null || true
fi

headline "Done"
echo "  Programs were left installed, and so were zellij's saved sessions."
echo "  To drop the session:  zellij delete-session --force $SESSION_HINT"

if ((SHOW_TOOLS)); then
    headline "Removing the programs"
    if [[ -z $tools ]]; then
        echo "  install.sh did not install any programs on this machine; they were"
        echo "  already here, so there is nothing of ours to remove."
    else
        echo "  install.sh installed these. Remove the ones you no longer want:"
        echo
        for t in $tools; do
            case $(uname -s):$t in
                Darwin:zed | Darwin:ghostty) echo "    brew uninstall --cask $t" ;;
                Darwin:*) echo "    brew uninstall $t" ;;
                Linux:zellij) echo "    rm $(tilde "$BIN_DIR")/zellij" ;;
                Linux:worktrunk) echo "    rm $(tilde "$BIN_DIR")/wt $(tilde "$BIN_DIR")/git-wt" ;;
                Linux:lazygit)
                    if [[ -x $BIN_DIR/lazygit ]]; then
                        echo "    rm $(tilde "$BIN_DIR")/lazygit"
                    else
                        echo "    sudo apt-get remove lazygit"
                    fi
                    ;;
                Linux:zed) echo "    zed --uninstall" ;;
                Linux:*) echo "    sudo apt-get remove $t" ;;
            esac
        done
    fi
fi
