# Worktree workflow: zellij auto-attach, `wts`, and `review`.
# Sourced from the end of ~/.zshrc by install.sh.

# Installed commands (wt-review, wts-open-tab) live here. Already on PATH on most
# Linux setups; stock macOS needs it added.
if [[ -d $HOME/.local/bin ]] && (( ! ${path[(Ie)$HOME/.local/bin]} )); then
    path=("$HOME/.local/bin" $path)
fi

# Both of these are normally done earlier in ~/.zshrc (oh-my-zsh runs compinit,
# and `wt config shell install` adds the init line). On a bare machine neither
# has happened, so do them here. Order matters: worktrunk only registers its
# completer if compdef already exists.
if (( ! $+functions[compdef] )); then
    autoload -Uz compinit && compinit
fi
if (( ! $+functions[wt] && $+commands[wt] )); then
    eval "$(command wt config shell init zsh)"
fi

: ${WORKFLOW_SESSION:=main}

# --- wts: worktree -> zellij tab ---------------------------------------------
#
#   wts feature/some-story   create or attach to the worktree, open/jump to its tab
#   wts                      pick a worktree interactively
#
# Anything `wt switch` accepts works here (`-`, `^`, `pr:12`, `--base`, ...).
wts() {
    emulate -L zsh

    if [[ -z $ZELLIJ ]]; then
        print -u2 "wts: not inside a zellij session"
        return 1
    fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print -u2 "wts: not inside a git repository"
        return 1
    fi

    # `wt switch` refuses an unknown branch without --create and refuses a known
    # one with it, so decide here. Only plain branch names qualify: shortcuts,
    # PR refs, paths, and flags are passed through untouched.
    local -a create
    local target=$1
    if [[ -n $target && $target != -* && $target != [@^] && $target != (pr|mr):* \
          && $target != *://* && ! -d $target ]]; then
        if ! git show-ref --verify --quiet "refs/heads/$target" \
           && [[ -z $(git for-each-ref --count=1 "refs/remotes/*/$target") ]]; then
            create=(--create)
        fi
    fi

    # --no-cd leaves this pane where it is; the new tab gets the worktree instead.
    command wt switch $create "$@" --no-cd \
        -x wts-open-tab -- '{{ branch }}' '{{ worktree_path }}'
}

# Completion: borrow worktrunk's own completer by presenting the command line as
# `wt switch ...`, so `wts <TAB>` offers exactly what `wt switch <TAB>` does.
_wts() {
    (( $+functions[_wt_lazy_complete] )) || return 1
    words=(wt switch "${(@)words[2,-1]}")
    (( CURRENT += 1 ))
    _wt_lazy_complete "$@"
}
(( $+functions[compdef] )) && compdef _wts wts

# --- review: branch diff in Zed ----------------------------------------------
alias review=wt-review

# --- auto-attach ---------------------------------------------------------------
#
# Every interactive terminal joins the one session: created on first use,
# attached if running, resurrected if dead. Kept last in this file because it
# blocks until zellij exits or detaches. No `exec`, so quitting zellij leaves a
# plain shell to fall back on.
#
# Skipped inside zellij itself, without a real terminal (scripts, `zsh -ic`),
# in editor-embedded terminals and agent shells, or when WORKFLOW_NO_ZELLIJ is set.
if [[ -o interactive && -t 0 && -t 1 \
      && -z $ZELLIJ && -z $WORKFLOW_NO_ZELLIJ \
      && -z $ZED_TERM && -z $INSIDE_EMACS && -z $CLAUDECODE \
      && $TERM_PROGRAM != vscode && $TERM_PROGRAM != zed \
      && $TERMINAL_EMULATOR != JetBrains* ]] \
   && (( $+commands[zellij] )); then
    zellij attach --create "$WORKFLOW_SESSION"
fi
