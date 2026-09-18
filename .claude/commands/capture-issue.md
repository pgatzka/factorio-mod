---
description: Capture a change request as a GitHub issue written as a user story, creating labels on demand
argument-hint: <change request in your own words>
allowed-tools: Bash(gh repo view:*), Bash(gh issue list:*), Bash(gh label list:*), Bash(gh label create:*), Bash(gh issue create:*), AskUserQuestion
---

Capture the following change request as a GitHub issue:

$ARGUMENTS

## Rules for the issue content

- The issue describes **wanted behavior**, never the work to be done.
- Leave out implementation details: no file names, functions, libraries, technical approach, task lists, or "how to fix" sections.
- When the request is phrased as a solution ("add a cache", "refactor X"), translate it into the behavior the user wants to experience. Ask when the underlying need is unclear.
- Write from the perspective of the person who benefits (player, mod user, server admin, contributor, maintainer, ...).
- Acceptance criteria describe observable outcomes, never implementation steps.
- One issue per story. When the request contains several independent stories, propose splitting it and capture each separately.

## Process

1. **Understand the request.**
   - When no change request was given above, ask for it.
   - Identify the role, the wanted behavior, and the benefit.
   - Ask clarifying questions with AskUserQuestion when any of the three cannot be derived. Never invent requirements.
2. **Check for duplicates.** Run `gh issue list --state all --search "<keywords>"`. When a likely duplicate exists, show it and ask whether to continue.
3. **Draft the issue** using the format below.
4. **Pick labels.**
   - Run `gh label list --limit 100` to see existing labels.
   - Reuse existing labels wherever they fit. Choose one type label (e.g. `enhancement`, `bug`) plus area labels where useful.
   - Create a missing label only when no existing one fits: `gh label create "<name>" --description "<short description>" --color <hex>`. Use lowercase kebab-case names that match the style of the existing labels.
5. **Confirm.** Show the title, body, and labels (marking which ones would be newly created) and ask for approval before anything is created on GitHub.
6. **Create.** After approval, create missing labels first, then the issue. Use the Bash tool and pass the body via heredoc:

   ```bash
   gh issue create --title "<title>" --label "<label1>,<label2>" --body-file - <<'EOF'
   <body>
   EOF
   ```

7. **Report** the issue URL and any labels that were created.

## Issue format

**Title:** short summary of the wanted behavior from the user's point of view (no "implement", "refactor", "add function").

**Body:**

```markdown
## User Story

As a <role>,
I want <behavior>,
so that <benefit>.

## Acceptance Criteria

- [ ] Given <context>, when <action>, then <observable outcome>
- [ ] ...

## Context

<Optional: current behavior, motivation, examples, screenshots, links. Omit the section when there is nothing to add.>
```

For a bug, the story states the expected behavior, and the Context section records the current behavior and how to reproduce it.
