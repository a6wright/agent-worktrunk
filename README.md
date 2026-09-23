# agent-worktrunk

A terminal workflow built on [zellij](https://zellij.dev), [worktrunk](https://worktrunk.dev),
[lazygit](https://github.com/jesseduffield/lazygit) and [Zed](https://zed.dev), with an
installer so it can be rebuilt on any machine.

## What you get

- **Every terminal lands in one zellij session**, `main`. It is created on first use, attached
  if running, and resurrected if it died (reboot included). The first tab is `control`: one pane.
  Open a second terminal window and it joins the same session.
- **`wts <branch>`** opens a worktree in its own tab, named after the branch: a full-height
  pane on the left, two stacked panes on the right, all three shells inside the worktree.

  ```
  ┌──────────────┬──────────────┐
  │              │              │
  │              ├──────────────┤
  │              │              │
  └──────────────┴──────────────┘
  ```

  worktrunk does the git work: a new branch is created, an existing one is attached to. If
  the tab is already open, `wts` jumps to it. Tab completion is worktrunk's own, and anything
  `wt switch` accepts works (`wts -`, `wts ^`, `wts pr:12`, `wts --base main new-branch`);
  bare `wts` opens its picker. The pane you ran it from stays where it was.
- **`wts remove [branch...]`** runs `wt remove` and then closes the tabs those worktrees
  had. Flags pass through (`wts remove -f`, `-D`, `-y`); with no branch it removes the
  current worktree. `wts remove <TAB>` completes like `wt remove <TAB>`. A branch that is
  itself named `remove` has to be opened with `wt switch`.
- **`Alt g`** opens lazygit in a floating pane covering 95% of the screen, in the focused
  pane's directory. One per tab: pressing it again closes it.
- **`review`** opens Zed with one multi-file diff of everything the branch changed since it
  forked from the default branch, committed or not. `review <ref>` compares against
  something else. The right-hand side is the live file, so edits land in the worktree.

## Install

```sh
git clone git@github.com:a6wright/agent-worktrunk.git ~/workspace/agent-worktrunk
cd ~/workspace/agent-worktrunk
./install.sh --dry-run   # see what it would do
./install.sh
```

Then open a new terminal.

The installer is safe to re-run; a second run changes nothing. It:

1. Installs whichever of git, zsh, jq, zellij, worktrunk, lazygit and Zed are missing.
   macOS uses Homebrew (and adds Ghostty). Linux uses apt where it can, prebuilt binaries
   into `~/.local/bin` for zellij and worktrunk, and Zed's own installer.
   `--no-tools` skips this step.
2. Links `config/zellij` to `~/.config/zellij`. An existing config is moved to a timestamped
   backup first.
3. Links the scripts in `bin/` into `~/.local/bin`. A file already there that is not ours is
   left alone and reported.
4. Appends one marked block to `~/.zshrc` that sources the workflow. The block points at a
   stable link in `~/.config/agent-worktrunk`, not at this repo, so if you move the repo you
   only need to run `install.sh` again.

Everything it does is recorded in `~/.local/state/agent-worktrunk/manifest`.

> The macOS path has not been run on a Mac yet. It shares all its logic with the Linux path
> except the `brew install` lines; use `--dry-run` first the first time.
>
> On a Mac, `Alt g` needs the terminal to send Option as Alt; otherwise Option-g types
> "©". The installer sets `macos-option-as-alt = true` in `~/.config/ghostty/config`
> (reload Ghostty's config with Cmd Shift , afterwards). For other terminals do it by
> hand: in Terminal.app enable "Use Option as Meta key" in the profile's Keyboard tab,
> in iTerm2 set the Option key to "Esc+" under Keys.

## Uninstall

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

Removes the `~/.zshrc` block, the links that point into this repo, and the `wt-review` cache,
then restores anything the installer had backed up. `~/.zshrc` ends up byte-for-byte as it was.
Programs are left installed; `--tools` prints the commands to remove the ones the installer
added. zellij's saved sessions are left alone too.

## Knobs

Set these before the workflow block in `~/.zshrc`, or in the environment:

| Variable | Default | Effect |
| --- | --- | --- |
| `WORKFLOW_SESSION` | `main` | Name of the session terminals attach to |
| `WORKFLOW_NO_ZELLIJ` | unset | Set to anything to skip auto-attach for that shell |
| `WTS_LAYOUT` | `worktree` | Layout name (in `config/zellij/layouts`) or path used for new tabs |

Auto-attach is also skipped inside zellij, in shells without a real terminal, and in the
embedded terminals of Zed, VS Code, JetBrains and Emacs.

Two repos with the same branch name do not share a tab: the second one is named
`<repo>:<branch>`.

## Making it yours

Nothing here is tied to one person's machine. The parts most worth changing:

- `config/zellij/layouts/worktree.kdl`: pane arrangement, or start a command in a pane
  (`pane command="nvim"`).
- `config/zellij/config.kdl`: the lazygit key, themes, any other zellij option. Note that
  zellij's own settings UI writes to this file too, since `~/.config/zellij` links here.
- `shell/workflow.zsh`: session name, when auto-attach is skipped.

Edits take effect without re-running the installer, because everything is symlinked.

## License

[MIT](LICENSE). Do what you like with it.

## Layout

```
install.sh, uninstall.sh, lib.sh   installer, its reverse, shared helpers
config/zellij/config.kdl           overrides only; zellij merges it over its defaults
config/zellij/layouts/             control.kdl (session), worktree.kdl (per-branch tab)
shell/workflow.zsh                 auto-attach, wts and its completion, review alias
bin/wts-open-tab                   finds or creates the tab; called by wts via `wt switch -x`
bin/wts-tab-ids                    which tabs belong to which worktrees; used by wts remove
bin/wt-review                      builds the diff pairs and hands them to Zed
```
