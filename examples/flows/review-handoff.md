# Review handoff

Who talks to whom when a branch goes up for review.

```mermaid
sequenceDiagram
    participant Dev
    participant Git
    participant Zed
    participant Reviewer
    Dev->>Git: commit and push
    Dev->>Zed: review
    Zed-->>Dev: branch diff
    Dev->>Reviewer: open a PR
    Reviewer-->>Dev: comments
    Dev->>Git: fixup commits
    Reviewer-->>Dev: approved
```

## Notes

- `->>` is a solid arrow (a request), `-->>` a dashed one (a reply).
- Try adding `Note over Dev,Git: CI runs here` between two lines.
