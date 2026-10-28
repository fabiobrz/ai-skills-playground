---
name: dependabot-pr
description: >-
  Turn a Dependabot pull request into a reviewed Jira draft and a locally fetched,
  Jira-key replacement branch. Trigger: when asked to process or replace a
  Dependabot PR, prepare a Jira component-upgrade issue, or create a Jira-backed
  replacement PR.
license: Apache-2.0
compatibility: >-
  Requires git, command, GitHub CLI tools (gh), Atlassian MCP tools, and access to 
  the internet.
allowed-tools: >-
  Bash(command -v:*)
  Bash(git rev-parse:*)
  Bash(git status --porcelain:*)
  Bash(git remote -v)
  Bash(gh auth status)
  Bash(gh pr view:*)
  Bash(gh pr diff:*)
  Bash(git fetch upstream:*)
  Bash(git blame:*)
  Bash(git show:*)
  Bash(git checkout --no-guess --no-overwrite-ignore:*)
  Bash(git commit --amend --only:*)
metadata:
  author: yersan
  version: "1.2"
  user-invocable: true
---

## Purpose

Process a Dependabot upgrade by verifying its upstream version links, drafting a Jira issue for review, creating that issue only after explicit approval, fetching the original PR into a Jira-key local branch, and giving the user commands to publish a replacement PR.

This skill uses the Agent Skill specification defined at: <https://agentskills.io/specification>

## Non-negotiable safeguards

- Check prerequisites before processing a PR: Git, GitHub CLI (`gh`), a Git repository with an identifiable upstream, GitHub CLI authentication, and Jira MCP access including issue creation capability must be available.
- Never create a Jira issue until the user has seen and explicitly approved the complete Jira draft. Approval of an earlier draft does not authorize a changed draft.
- Never use a test Jira issue to probe access. Use read-only Jira project and issue-type metadata tools to establish whether the project and `Component Upgrade` issue type are available. If the tools cannot establish create access, say so and do not assume the user is authorized.
- After successful Jira creation, fetch the original PR using the required `git fetch upstream pull/<number>/head:<JIRA_KEY>` refspec, after verifying `upstream` points to the PR's source repository and the local branch does not already exist.
- Reword only the fetched commit in Step 8, after separate approval of the exact message.
- Never push a branch or perform a GitHub write. Do not create, comment on, close, or merge a PR. Give the user copy-paste commands for those actions instead.
- Never overwrite a pre-existing or unrelated branch or user work. Amend only the newly fetched Jira-key branch, after confirming the worktree is clean.
- Do not guess dependency tags, release notes, Jira project, required fields, fork owner, or remotes. Verify them or ask the user.
- Do not treat a generic GitHub releases index, a tag page, or a tag annotation as release notes. Set release notes to `null`/unavailable unless version-specific release notes or a version-specific changelog entry are verified.

## Workflow

### [ ] Step 1: Parse the input and verify prerequisites

Accept a PR URL, `<owner>/<repo>#<number>`, or a PR number. For a number alone, use the current repository and its `upstream` remote to identify the repository. If that is ambiguous, ask for the repository.

Before retrieving or changing anything, check:

1. `command -v git` and `command -v gh` succeed.
2. `git rev-parse --show-toplevel` succeeds.
3. `gh auth status` succeeds for the GitHub host containing the PR. Do not reveal tokens or credentials in output.
4. The `upstream` remote exists and can be matched to the source repository. Do not silently add or repoint remotes.
5. Jira MCP tools are available. Discover the available tools and their schemas rather than assuming a tool name. Confirm the Jira identity with the current-user tool when available.
6. The Jira site and project are accessible for issue creation: use the Jira project listing with its create action (or equivalent read-only permission metadata), list issue types, and check the creation fields for the chosen type. Never probe by creating an issue. If create permission cannot be determined from available read-only tools, explain the limitation before asking for approval to create.

If any required CLI, authentication, repository, or MCP prerequisite is missing, stop and tell the user what is unavailable. Do not start the Jira or fetch workflow.

### [ ] Step 2: Retrieve and verify the Dependabot PR

Use `gh` read-only commands, targeting the repository explicitly:

```bash
gh pr view <number> --repo <owner>/<repo> \
  --json title,body,url,author,state,isDraft,baseRefName,headRefName,commits,files
gh pr diff <number> --repo <owner>/<repo>
```

Confirm it is the requested Dependabot PR. Extract:

- PR number, URL, state, base branch, and head branch
- dependency name(s), old version(s), and proposed version(s)
- all artifacts affected by a version property bump
- source/upstream dependency repository
- tag, comparison, and release-note/changelog links, if present
- changed paths and commit(s)

If the PR was already superseded, already has a Jira reference, or is not a Dependabot dependency update, report that and ask whether to continue. Do not create a duplicate Jira by default.

### [ ] Step 3. Resolve dependency links

Use the PR body as the primary source. Dependabot bodies commonly contain:

- a dependency repository link
- a compare link of the form `.../compare/<old-tag>...<new-tag>`
- an optional release-notes link

Verify that both compare endpoints correspond to the versions in the PR and that the proposed tag exists in the dependency repository. A tag link should point to the exact proposed version, for example `https://github.com/<owner>/<repo>/tree/<tag>` or the corresponding tag page. Use a `/releases/tag/...` link only if an actual release exists for that tag.

When links are absent or unclear, use read-only GitHub metadata or the dependency's published SCM metadata to discover the source repository and tag convention. Do not construct an unverified tag or compare URL. If confidence remains insufficient, ask the user.

For release notes, prefer version-specific release notes linked by the PR or a verified release page. If unavailable, check for a version-specific changelog entry at the tagged version. Include a link only when its content actually documents that version or search on Internet if there are any release notes associated to this component upgrade version.

If the release notes cannot be inferred at this point, we can try to check whether there is a Jira that contains this information in its description. To do so, do a git blame and find out
the latest commit that modified this line in the code by inspecting the local repository. If the commit message contains a Jira key, use it to retrieve the description from Jira and inspect if there is any release notes associated to this component upgrades. If so, use it to search what is the release-notes of the current upgraded version.

Otherwise, if the release-notes cannot be inferred, record `release-notes: null` and omit that line from the Jira description.

Report the discovered dependency details and links before drafting the Jira. The link data should be represented as:

```json
{
  "tag": "<verified proposed-version tag URL>",
  "diff": "<verified old-to-new comparison URL>",
  "release-notes": "<verified version-specific URL or null>"
}
```

### [ ] Step 4. Determine the Jira project and draft the issue

Map known repositories:

| Upstream repository    | Jira project |
| ---------------------- | ------------ |
| `wildfly/wildfly`      | `WFLY`       |
| `wildfly/wildfly-core` | `WFCORE`     |

For other repositories, ask the user for the Jira project key. Verify the project is accessible and supports the `Component Upgrade` issue type. If the type is absent or required fields cannot be determined, stop and ask; do not substitute another issue type without approval.

Check for an existing Jira associated with the PR or dependency upgrade using available Jira search tools and PR references. If a likely duplicate exists, show it and ask whether to reuse it. Do not create a duplicate automatically.

Use a concise upgrade summary, matching the example convention:

```text
Upgrade <dependency display name> to <new version>
```

For version-property upgrades affecting multiple artifacts, mention the property/dependency in the summary and list all affected artifacts and versions in the description. Do not invent a component, priority, assignee, or other Jira field. Include only fields confirmed from user instructions, project metadata, or Jira requirements. Ask the user if a required field is unknown.

Draft description format:

```text
Upgrade <dependency display name> from <old version> to <new version>.

Tag: <tag URL>
Diff: <diff URL>
Release notes: <release-notes URL>

Dependabot PR: <original PR URL>
```

Omit the `Release notes` line if unavailable. Include all affected artifacts and their old/new versions where applicable.

### [ ] Step 5. Show the complete Jira draft

Show the complete Jira draft to the user, including project, issue type, summary, description, and every other proposed field:

```text
=== Jira Issue Draft ===
Project: <project key>
Issue type: Component Upgrade
Summary: <summary>
Description:
<full description>
Additional fields: <fields, or None>

Create this Jira issue using this exact draft?
```

### [ ] Step 6. Wait for a user approval before creating the Jira

Wait for clear, explicit approval of the exact Jira draft. If the user asks for edits, revise and show the complete draft again. Do not call a Jira creation tool until the user approves the final displayed draft.

### [ ] Step 7. Create the approved Jira issue

After explicit approval, call the discovered Jira MCP issue-creation tool with the exact approved project, issue type, summary, description, and additional fields. Use the authenticated Jira site selected in preflight; do not assume a cloud ID if it has not been verified.

If the result is ambiguous or times out, check for an issue matching the approved summary/PR before retrying. Do not blindly retry and risk a duplicate. Report the actual Jira key and URL returned by Jira. The Jira key from the creation result is the branch name for the next step.

If Jira creation fails because of access, fields, or project configuration, report the error and stop; do not fetch or prepare a replacement branch until the issue exists.

### [ ] Step 8. Fetch the PR and optionally reword its commit

After Jira creation succeeds:

1. Verify `upstream` is the PR source and no local `<JIRA_KEY>` branch exists. Fetch the PR head without checking it out or changing the current worktree:

   ```bash
   git fetch upstream "pull/${PR_NUMBER}/head:${JIRA_KEY}"
   ```

2. Verify the branch points to the PR head and the PR has exactly one commit with one parent. If not, leave it as fetched and ask how to proceed; do not rewrite it.
3. Determine the base branch and push remote from repository metadata. Check `git status --porcelain` before offering to switch; if the worktree is not clean, stop and ask how to proceed.
4. Prepare the commit message from the Jira key, approved summary, and canonical Jira URL:

   ```text
   [<JIRA_KEY>] <approved Jira summary>

   Jira issue: <canonical Jira issue URL>
   ```

   Show the exact message and get separate approval to switch to `<JIRA_KEY>` and amend its commit with that message. Explain that this changes the SHA, does not preserve any original signature, and leaves `<JIRA_KEY>` checked out. Jira approval does not count. If declined, leave the branch unchanged and continue with Step 9.

5. After approval, switch to the branch:

   ```bash
   git checkout --no-guess --no-overwrite-ignore "${JIRA_KEY}"
   ```
   Then amend only the message. The tree, parent, and author should remain unchanged:

   ```bash
   git commit --amend --only \
     -m "[${JIRA_KEY}] <approved Jira summary>" \
     -m "Jira issue: <canonical Jira issue URL>"
   ```

   Verify the new message and that the tree, parent, and author are unchanged. If switching, amending, or verification fails, stop and report the issue; do not modify Git configuration. Leave the Jira-key branch checked out.

If `upstream` is missing, mismatched, inaccessible, or the fetch fails, stop and report the precise issue. Do not add/remap a remote or try alternate destructive commands automatically.

### [ ] Step 9. Present replacement PR details and manual commands

Show the Jira-backed replacement PR plan, based on verified metadata:

```text
=== Replacement PR ===
Jira: <JIRA_KEY> — <Jira URL>
Repository: <upstream owner>/<repository>
Branch: <JIRA_KEY>
Base: <verified base branch>
Title: [<JIRA_KEY>] <approved Jira summary>
Body: Jira issue: <Jira URL>
Source Dependabot PR: <original PR URL>
Local branch fetched: <JIRA_KEY>
Original fetched commit: <original PR head SHA>
Local branch head: <verified local head SHA>
```

Provide commands for the user to publish the branch and create the new PR. Use only verified remotes, fork owner, repository, and base branch. If the correct push remote or fork cannot be determined, give a template with explicit placeholders and ask the user to fill them; do not guess.

```bash
git push <verified-fork-remote> <JIRA_KEY>

gh pr create \
  --repo <upstream-owner>/<repository> \
  --head <fork-owner>:<JIRA_KEY> \
  --base <base-branch> \
  --title "[<JIRA_KEY>] <approved Jira summary>" \
  --body "Jira issue: <Jira URL>"
```

Do not execute these commands. Do not automatically comment on or close the original Dependabot PR. Optionally provide a separate, clearly labeled command the user can run after the replacement PR exists to explain that it supersedes the Dependabot PR; never run it.

# General notes

## Approval rules at a glance

| Action                                           | Allowed without approval?                                                              |
| ------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Read PR metadata, diffs, tags, and Jira metadata | Yes, after prerequisite checks                                                         |
| Present a Jira draft                             | Yes                                                                                    |
| Create a Jira issue                              | **No — explicit approval of the exact draft is required**                              |
| Fetch PR head into local `<JIRA_KEY>` ref        | Only after Jira creation succeeds; stop if it would overwrite or disturb existing work |
| Switch to the fetched `<JIRA_KEY>` branch        | Only with approval in Step 8; leave it checked out                                    |
| Reword the fetched single-commit PR head        | Only after approval of the exact resolved message in Step 8; stop for multi-commit PRs |
| Rewrite any other commits                       | **No — requires a separate user request and approval**                                |
| Push, create/comment/close/merge GitHub PR       | **Never — provide commands for the user to run**                                       |

## Commands

```bash
command -v git
command -v gh
git rev-parse --show-toplevel
git remote -v
gh auth status
gh pr view <number> --repo <owner>/<repo> --json title,body,url,author,state,isDraft,baseRefName,headRefName,commits,files
gh pr diff <number> --repo <owner>/<repo>
git fetch upstream "pull/${PR_NUMBER}/head:${JIRA_KEY}"
```
