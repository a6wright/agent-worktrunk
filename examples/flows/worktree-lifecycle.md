# Worktree lifecycle

What happens from `wts <branch>` to `wts remove`.

```mermaid
graph TD
    A[wts feature-x] --> B{Branch exists?}
    B -->|no| C[Create branch]
    B -->|yes| D[Attach worktree]
    C --> D
    D --> E[Open zellij tab]
    E --> F[Hack, commit, review]
    F --> G[wts remove]
    G --> H[Close tab]
```

The same thing left to right, which suits wide screens:

```mermaid
graph LR
    new[wts] --> tab[Tab open] --> work[Work] --> done[wts remove]
```

## Try

- Add a `B -->|yes, and open| E` edge and see how the routing changes.
- Change `graph TD` to `graph LR`.
