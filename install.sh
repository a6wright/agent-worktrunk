#!/usr/bin/env bash
# Install the worktree workflow: zellij + worktrunk + lazygit + zed.
#
# Usage: ./install.sh [--dry-run] [--no-tools]
#
#   --dry-run    print what would happen, change nothing
#   --no-tools   only link configs and scripts; do not install missing programs
#
# Safe to re-run: every step checks first, and a second run changes nothing.
# Everything done is recorded in a manifest so uninstall.sh can reverse exactly
# that and nothing else.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib.sh
source "$REPO/lib.sh"

INSTALL_TOOLS=1
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=1 ;;
        --no-tools) INSTALL_TOOLS=0 ;;
        -h | --help)
            sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p;}' "$0"
            exit 0
            ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

# --- tools --------------------------------------------------------------------

# Programs this run installed (as opposed to found), for the manifest and summary.
INSTALLED=()
FAILED=()

# try <name> <command...>: install one tool, recording the result. A failure is
# reported and the run carries on; the rest of the setup is still worth having.
try() {
    local name=$1
    shift
    step "installing $name"
    if ((DRY_RUN)); then
        would "$*"
        return
    fi
    if "$@"; then
        INSTALLED+=("$name")
        manifest_add tool "$name"
    else
        FAILED+=("$name")
        warn "could not install $name"
    fi
}

install_tools_macos() {
    if ! have brew; then
        die "Homebrew is required on macOS. Install it, then re-run:
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
    have git || try git brew install git
    have jq || try jq brew install jq
    have zellij || try zellij brew install zellij
    have wt || try worktrunk brew install worktrunk
    have lazygit || try lazygit brew install lazygit
    have fzf || try fzf brew install fzf
    have glow || try glow brew install glow
    have moor || try moor brew install moor
    have termaid || try termaid brew install termaid
    have gh || try gh brew install gh
    have tuicr || try tuicr brew install tuicr
    have zed || try zed brew install --cask zed
    [[ -d /Applications/Ghostty.app ]] || have ghostty || try ghostty brew install --cask ghostty
}

# Release asset architecture names: Go tools say arm64, Rust tools aarch64.
goarch() {
    case $(uname -m) in
        x86_64) echo x86_64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) return 1 ;;
    esac
}
rustarch() {
    case $(uname -m) in
        x86_64) echo x86_64 ;;
        aarch64 | arm64) echo aarch64 ;;
        *) return 1 ;;
    esac
}

# from_github <owner/repo> <binary> <asset-regex>: the latest release tarball
# whose name matches, its binary put in ~/.local/bin wherever the archive keeps it.
from_github() {
    local repo=$1 bin=$2 pattern=$3 url tmp
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
        jq -r --arg p "$pattern" '.assets[].browser_download_url | select(test($p; "i"))' |
        head -n1)
    [[ -n $url ]] || return 1
    tmp=$(mktemp -d)
    curl -fsSL "$url" | tar -xz -C "$tmp" || { rm -rf "$tmp"; return 1; }
    mkdir -p "$BIN_DIR"
    find "$tmp" -type f -name "$bin" -exec mv {} "$BIN_DIR/$bin" \;
    rm -rf "$tmp"
    [[ -x $BIN_DIR/$bin ]]
}

# moor ships bare binaries, and none for arm64 Linux.
moor_from_github() {
    local url
    url=$(curl -fsSL https://api.github.com/repos/walles/moor/releases/latest |
        jq -r '.assets[].browser_download_url | select(endswith("-linux-amd64"))' | head -n1)
    [[ -n $url ]] || return 1
    mkdir -p "$BIN_DIR"
    curl -fsSL -o "$BIN_DIR/moor" "$url" && chmod +x "$BIN_DIR/moor"
}

ensure_binstall() {
    have cargo-binstall && return 0
    curl -L --proto '=https' --tlsv1.2 -sSf \
        https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
    export PATH="$HOME/.cargo/bin:$PATH"
    have cargo-binstall
}

# Python CLIs, each in its own environment, with the command in ~/.local/bin.
pytool() {
    if have uv; then
        uv tool install "$1"
    elif have pipx; then
        pipx install "$1"
    else
        warn "$1 needs uv or pipx (sudo apt-get install pipx)"
        return 1
    fi
}

# Prebuilt binaries straight into ~/.local/bin, so a machine with no Rust
# toolchain does not need ~/.cargo/bin on PATH.
binstall() {
    ensure_binstall && cargo-binstall --no-confirm --install-path "$BIN_DIR" "$@"
}

install_tools_linux() {
    local apt_pkgs=() p
    if have apt-get; then
        for p in git zsh jq curl fzf gh; do have "$p" || apt_pkgs+=("$p"); done
        if ! have lazygit && apt-cache show lazygit >/dev/null 2>&1; then
            apt_pkgs+=(lazygit)
        fi
        if ((${#apt_pkgs[@]})); then
            try "${apt_pkgs[*]}" sudo apt-get install -y "${apt_pkgs[@]}"
        fi
    else
        for p in git zsh jq curl fzf gh; do
            have "$p" || warn "$p is missing; install it with your package manager"
        done
    fi

    if ! have jq || ! have curl; then
        ((DRY_RUN)) || die "jq and curl are needed for the remaining installs"
    fi

    # Not packaged on older Ubuntu/Debian; fall back to the upstream release.
    # Skipped when apt is about to provide it (matters only under --dry-run).
    if ! have lazygit && [[ " ${apt_pkgs[*]-} " != *" lazygit "* ]]; then
        try lazygit from_github jesseduffield/lazygit lazygit "_linux_$(goarch)\\.tar\\.gz$"
    fi

    mkdir -p "$BIN_DIR"
    have zellij || try zellij binstall zellij
    have wt || try worktrunk binstall worktrunk
    have glow || try glow from_github charmbracelet/glow glow "_linux_$(goarch)\\.tar\\.gz$"
    have tuicr || try tuicr from_github agavra/tuicr tuicr "-$(rustarch)-unknown-linux-musl\\.tar\\.gz$"
    if ! have moor; then
        if [[ $(uname -m) == x86_64 ]]; then
            try moor moor_from_github
        else
            note "moor has no build for $(uname -m); wt-md pages with less instead (q, not Esc, leaves a file)"
        fi
    fi
    have termaid || try termaid pytool termaid
    have zed || try zed sh -c 'curl -fsSL https://zed.dev/install.sh | sh'
    have ghostty || note "Ghostty not found. Any terminal works; see https://ghostty.org/docs/install/binary"
}

# gh-dash is a gh extension, and installing one needs a logged-in gh.
install_gh_dash() {
    have gh || return 0
    gh extension list 2>/dev/null | grep -q 'gh-dash' && return 0
    if ! gh auth status >/dev/null 2>&1; then
        note "gh-dash (Alt d) needs gh logged in: run 'gh auth login', then ./install.sh again"
        return 0
    fi
    try gh-dash gh extension install dlvhdr/gh-dash
}

# --- links ----------------------------------------------------------------------

# link <source> <dest> <on-conflict>
#   on-conflict = backup   move whatever is in the way to a timestamped backup
#               = skip     leave it alone and report it
link() {
    local src=$1 dest=$2 conflict=$3 backup

    if [[ -L $dest && $(readlink "$dest") == "$src" ]]; then
        ok "$(tilde "$dest") already linked"
        manifest_add link "$dest"
        return
    fi

    if [[ -e $dest || -L $dest ]]; then
        # A link we made earlier (say, before the repo moved) is ours to replace.
        if [[ -L $dest ]] && manifest_has link "$dest"; then
            run rm "$dest"
        elif [[ $conflict == backup ]]; then
            backup="$dest.backup-$(date +%Y%m%d-%H%M%S)"
            step "backing up $(tilde "$dest") to $(tilde "$backup")"
            run mv "$dest" "$backup"
            ((DRY_RUN)) || manifest_add backup "$dest" "$backup"
        else
            warn "$(tilde "$dest") exists and is not ours; left alone"
            SKIPPED+=("$(tilde "$dest")")
            return
        fi
    fi

    step "linking $(tilde "$dest")"
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$src" "$dest"
    ((DRY_RUN)) || manifest_add link "$dest"
}

SKIPPED=()

# --- zshrc ------------------------------------------------------------------------

install_zshrc_block() {
    local zshrc=$HOME/.zshrc
    if [[ -f $zshrc ]] && grep -Fq "$MARK_BEGIN" "$zshrc"; then
        ok "$(tilde "$zshrc") already sources the workflow"
        return
    fi
    step "adding the workflow block to ~/.zshrc"
    if ((DRY_RUN)); then
        would "append to $zshrc:"
        zshrc_block | sed 's/^/           /'
        return
    fi
    # Separate from existing content with a blank line, unless the file is new.
    [[ -s $zshrc ]] && printf '\n' >>"$zshrc"
    zshrc_block >>"$zshrc"
    manifest_add zshrc "$zshrc"
}

# --- ghostty ----------------------------------------------------------------------

# On a Mac, Ghostty composes Option-g into "©" unless told to send Option as Alt.
install_ghostty_block() {
    [[ $OS == Darwin ]] || return 0
    [[ -d /Applications/Ghostty.app ]] || have ghostty || return 0
    local cfg=$GHOSTTY_CONFIG
    local other="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    if [[ -f $cfg ]] && grep -Fq "$MARK_BEGIN" "$cfg"; then
        ok "$(tilde "$cfg") already sends Option as Alt"
        return
    fi
    # A choice already made in either file Ghostty reads is theirs, not ours.
    if grep -Eqs '^[[:space:]]*macos-option-as-alt[[:space:]]*=' "$cfg" "$other"; then
        note "Ghostty already sets macos-option-as-alt; left alone (Alt g needs it on)"
        return
    fi
    step "setting macos-option-as-alt in $(tilde "$cfg")"
    if ((DRY_RUN)); then
        would "append to $cfg:"
        ghostty_block | sed 's/^/           /'
        return
    fi
    mkdir -p "$(dirname "$cfg")"
    [[ -s $cfg ]] && printf '\n' >>"$cfg"
    ghostty_block >>"$cfg"
    manifest_add ghostty "$cfg"
    GHOSTTY_CHANGED=1
}
GHOSTTY_CHANGED=0

# --- claude code -------------------------------------------------------------------

# tuicr's own Claude Code skill, from the release matching the installed tuicr:
# with it Claude opens a review pane beside the chat and reads the comments
# back. Refreshed when tuicr is upgraded; a skill of the same name that we did
# not put there is left alone.
install_tuicr_skill() {
    local dest=$HOME/.claude/skills/tuicr version tmp src
    [[ -d $HOME/.claude ]] || return 0
    if ! have tuicr; then
        ((DRY_RUN)) || note "tuicr is missing, so its Claude Code skill was skipped"
        return 0
    fi
    version=$(tuicr --version | awk '{ print $2 }')
    if [[ -e $dest ]] && ! manifest_has skill "$dest"; then
        warn "$(tilde "$dest") exists and is not ours; left alone"
        SKIPPED+=("$(tilde "$dest")")
        return
    fi
    if [[ -f $dest/.tuicr-version && $(cat "$dest/.tuicr-version") == "$version" ]]; then
        ok "tuicr $version skill for Claude Code"
        return
    fi
    step "installing the tuicr $version skill for Claude Code in $(tilde "$dest")"
    if ((DRY_RUN)); then
        would "fetch skills/tuicr from agavra/tuicr v$version"
        return
    fi
    tmp=$(mktemp -d)
    if curl -fsSL "https://codeload.github.com/agavra/tuicr/tar.gz/refs/tags/v$version" |
        tar -xz -C "$tmp" &&
        src=$(find "$tmp" -type d -path '*/skills/tuicr' | head -n1) && [[ -f $src/SKILL.md ]]; then
        rm -rf "$dest"
        mkdir -p "$(dirname "$dest")"
        mv "$src" "$dest"
        echo "$version" >"$dest/.tuicr-version"
        manifest_add skill "$dest"
    else
        FAILED+=("tuicr-skill")
        warn "could not fetch the tuicr skill for v$version"
    fi
    rm -rf "$tmp"
}

# --- main -------------------------------------------------------------------------

((DRY_RUN)) && note "dry run: nothing will be changed"

OS=$(uname -s)
if ((INSTALL_TOOLS)); then
    headline "Tools"
    case $OS in
        Darwin) install_tools_macos ;;
        Linux) install_tools_linux ;;
        *) die "unsupported OS: $OS" ;;
    esac
    install_gh_dash
    for t in git zsh jq zellij wt lazygit fzf glow moor termaid gh tuicr zed; do
        if have "$t"; then
            ok "$t"
        elif ! ((DRY_RUN)); then
            warn "$t still missing"
        fi
    done
else
    note "skipping tool installs (--no-tools)"
fi

headline "Config"
link "$REPO/config/zellij" "$CONFIG_HOME/zellij" backup
link "$REPO/config/tuicr" "$CONFIG_HOME/tuicr" backup
link "$REPO/config/gh-dash" "$CONFIG_HOME/gh-dash" backup
# A stable path for ~/.zshrc to source, so it never mentions where the repo is.
link "$REPO/shell/workflow.zsh" "$WORKFLOW_LINK" backup

headline "Commands"
for f in "$REPO"/bin/*; do
    [[ -f $f && -x $f ]] || continue
    link "$f" "$BIN_DIR/$(basename "$f")" skip
done

headline "Claude Code"
install_tuicr_skill

headline "Shell"
install_zshrc_block
install_ghostty_block
case :$PATH: in
    *:"$BIN_DIR":*) ;;
    *) note "$(tilde "$BIN_DIR") is not on PATH yet; the workflow block adds it for zsh" ;;
esac
case ${SHELL:-} in
    */zsh) ;;
    *) note "your login shell is ${SHELL:-unknown}; this workflow is zsh-only. Switch with: chsh -s \"\$(command -v zsh)\"" ;;
esac

headline "Done"
((${#INSTALLED[@]})) && echo "  installed:  ${INSTALLED[*]}"
((${#FAILED[@]})) && echo "  FAILED:     ${FAILED[*]}"
((${#SKIPPED[@]})) && echo "  left alone: ${SKIPPED[*]}"
if ((DRY_RUN)); then
    echo "  dry run only; re-run without --dry-run to apply"
else
    cat <<EOF
  Open a new terminal to land in the "$SESSION_HINT" zellij session.
    wts <branch>   open a worktree in its own tab (tab-completes)
    wts remove     remove a worktree and close its tab
    Alt g          lazygit in a floating pane (one per tab; Esc closes it)
    Alt m          the repo's markdown, rendered, Mermaid included (Esc closes it)
    Alt r          review the branch in tuicr; comments reach Claude via /tuicr
    Alt d          GitHub PRs in gh-dash (T reviews one in tuicr)
    review         branch diff in Zed
  Undo with ./uninstall.sh
EOF
    ((GHOSTTY_CHANGED)) && echo "  Ghostty: reload its config (Cmd Shift ,) or restart it, so Alt g works."
fi
((${#FAILED[@]} == 0))
