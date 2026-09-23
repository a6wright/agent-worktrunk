# Shared by install.sh and uninstall.sh. Sourced, not executed.
# Written for bash 3.2 (what macOS ships): no associative arrays, no mapfile.
# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables below are used by the scripts that source this

DRY_RUN=${DRY_RUN:-0}

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/agent-worktrunk
MANIFEST=$STATE_DIR/manifest
BIN_DIR=$HOME/.local/bin
WORKFLOW_LINK=$CONFIG_HOME/agent-worktrunk/workflow.zsh
GHOSTTY_CONFIG=$CONFIG_HOME/ghostty/config
SESSION_HINT=${WORKFLOW_SESSION:-main}

MARK_BEGIN='# >>> agent-worktrunk >>>'
MARK_END='# <<< agent-worktrunk <<<'

# What install.sh appends to ~/.zshrc. It names the stable link rather than the
# repo, so moving the repo only needs a re-run of install.sh.
zshrc_block() {
    cat <<EOF
$MARK_BEGIN
# Worktree workflow (zellij + worktrunk). Managed by agent-worktrunk/install.sh;
# remove with uninstall.sh. Keep this at the end of the file.
[ -r "\${XDG_CONFIG_HOME:-\$HOME/.config}/agent-worktrunk/workflow.zsh" ] && source "\${XDG_CONFIG_HOME:-\$HOME/.config}/agent-worktrunk/workflow.zsh"
$MARK_END
EOF
}

# What install.sh appends to Ghostty's config on macOS. Without it Option-g
# types "©" and zellij never sees Alt g.
ghostty_block() {
    cat <<EOF
$MARK_BEGIN
# Send Option as Alt, so zellij's Alt keys (Alt g for lazygit) reach it.
# Managed by agent-worktrunk/install.sh; remove with uninstall.sh.
macos-option-as-alt = true
$MARK_END
EOF
}

# --- output -------------------------------------------------------------------
if [[ -t 1 ]]; then
    _b=$'\033[1m' _g=$'\033[32m' _y=$'\033[33m' _r=$'\033[31m' _d=$'\033[2m' _0=$'\033[0m'
else
    _b='' _g='' _y='' _r='' _d='' _0=''
fi
headline() { printf '\n%s%s%s\n' "$_b" "$*" "$_0"; }
step() { printf '  %s->%s %s\n' "$_b" "$_0" "$*"; }
ok() { printf '  %sok%s %s\n' "$_g" "$_0" "$*"; }
note() { printf '  %snote%s %s\n' "$_d" "$_0" "$*"; }
warn() { printf '  %swarn%s %s\n' "$_y" "$_0" "$*" >&2; }
would() { local m="$*"; printf '     %swould:%s %s\n' "$_d" "$_0" "${m//$HOME/\~}"; }
die() {
    printf '%serror%s %s\n' "$_r" "$_0" "$*" >&2
    exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }
tilde() { printf '%s' "${1/#$HOME/\~}"; }

# run <command...>: execute, or under --dry-run just print.
run() {
    if ((DRY_RUN)); then
        would "$*"
    else
        "$@"
    fi
}

# --- manifest -----------------------------------------------------------------
# One tab-separated record per line: <kind> <path-or-name> [<extra>]
#   link    <dest>              a symlink we created
#   backup  <original> <backup> something we moved out of the way
#   tool    <name>              a program we installed (not merely found)
#   zshrc   <file>              a file we appended the block to
#   ghostty <file>              a Ghostty config we appended the block to
#   skill   <dir>               a Claude Code skill we put in place

manifest_has() { # kind value
    [[ -f $MANIFEST ]] && grep -Fxq -- "$1"$'\t'"$2" "$MANIFEST"
}

manifest_add() { # kind value [extra]
    ((DRY_RUN)) && return 0
    local line="$1"$'\t'"$2"
    [[ -n ${3:-} ]] && line+=$'\t'"$3"
    mkdir -p "$STATE_DIR"
    [[ -f $MANIFEST ]] && grep -Fxq -- "$line" "$MANIFEST" && return 0
    printf '%s\n' "$line" >>"$MANIFEST"
}

# manifest_list <kind>: print the records of one kind, without the kind column.
manifest_list() {
    [[ -f $MANIFEST ]] || return 0
    awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$MANIFEST"
}
