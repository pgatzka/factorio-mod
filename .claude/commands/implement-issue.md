---
description: Implement a GitHub issue end to end - analyze, branch, implement, commit, push, open PR, request approval
argument-hint: [issue-id]
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh pr list:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh repo view:*), Bash(git status:*), Bash(git fetch:*), Bash(git switch:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git diff:*), Bash(git log:*), Agent, AskUserQuestion
---

Implement GitHub issue: $ARGUMENTS

Invoking this command is the explicit request to commit, push, and open a pull request for this issue. Run the steps in order and stop with a clear report when a step fails.

## 1. Select and read the issue

- With an issue id given: `gh issue view <id> --json number,title,body,labels,state,assignees,comments`.
- Without an issue id: run `gh issue list --state open --json number,title,labels,assignees,createdAt`, then choose one:
  - Skip issues that already have an open PR or a branch starting with `<id>-` (`gh pr list`, `git branch -a`).
  - Prefer unassigned issues, then bugs over enhancements, then the oldest.
  - State which issue was chosen and why, then continue.
- Stop when the issue is closed or no open issue exists.
- Issues describe wanted behavior as a user story. Treat the acceptance criteria as the definition of done. Ask with AskUserQuestion when the wanted behavior is unclear; never invent requirements.

## 2. Analyze the code

- Delegate to the `code-analyzer` agent (Agent tool, `subagent_type: "code-analyzer"`).
- Give it the user story, the acceptance criteria, and the question: which code, prototypes, settings, locale, config, tests, and docs are involved in this behavior, and what depends on them.
- Run several code-analyzer agents in parallel when the issue touches independent areas.
- Derive a short implementation plan from the findings. Work from the reported `path:line` references instead of repeating the searches.

## 3. Create the branch

- Branch name: `<issue-id>-<title>` where the title is converted to lowercase and spaces are replaced with `-`. No `feature/`, `bug/`, or other prefixes.
  - Example: issue 267 "Setup OAuth2" becomes `267-setup-oauth2`.
  - Also drop characters that are invalid in git branch names (`~ ^ : ? * [ \` and similar) and collapse repeated `-`.
- Require a clean working tree (`git status --porcelain`). With uncommitted changes present, stop and ask how to proceed.
- Branch from the up-to-date default branch: `git fetch origin`, then `git switch -c <branch> origin/<default-branch>`.
- When the branch already exists, switch to it and continue there.

## 4. Implement

- Implement exactly what the acceptance criteria require; keep unrelated refactoring out of the change.
- Match the surrounding code style and follow the project's `CLAUDE.md`.
- Add or update tests, locale strings, changelog, and docs where the project has them.
- Verify: run the project's tests, linters, and checks when they exist. Walk through every acceptance criterion and confirm it is met. Fix failures before continuing.

## 5. Commit

- Review `git status` and `git diff`, then stage the relevant files by name. Keep secrets, `.env` files, and unrelated files out of the commit.
- Write a concise commit message that explains the change and references the issue (`#<id>`). Follow the commit style found in `git log`.
- Use several commits when the change has clearly separable parts.

## 6. Push

- `git push -u origin <branch>`

## 7. Open the pull request

- `gh pr create --base <default-branch> --head <branch>` with:
  - **Title:** the issue title.
  - **Body:** a summary of what changed and why, how each acceptance criterion is met, how it was verified, and `Closes #<id>`. Pass the body via `--body-file -` and a heredoc.
- Reuse the issue's labels on the PR where they apply.

## 8. Request user approval

- Report: issue, branch, commits, PR URL, verification results, and any acceptance criterion that is not fully met.
- Ask the user with AskUserQuestion to review the pull request: **Approve** or **Request changes**.
  - On requested changes: implement them on the same branch, commit, push, and ask again.
  - On approval: finish with a final summary. Leave merging to the user unless they ask for it.
