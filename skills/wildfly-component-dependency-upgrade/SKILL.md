---
name: webservices-dependency-upgrade
description: Test and validate WildFly XML Web Services component dependency upgrades from dependabot PRs
args: pr_url
---

# WildFly XML Web Services Component Upgrade Validation

You are executing a skill to validate Web Services component dependency upgrades in WildFly. 
This workflow tests PRs that update dependencies in the webservices group. Such PRs are currently created by 
dependabot in most cases (see .github/dependabot.yml), but it applies to Prs that can be opened by developers on 
a different input (e.g.: a component upgrade report).

## Parameters

Parse the args string to extract:
- `pr_url` (required): PR URL or PR number (assume wildfly/wildfly if just a number)

Both the WildFly and jbossws-cxf repositories are cloned automatically. Derive a workspace root from the PR number:

```
WORKSPACE=/tmp/wildfly-upgrade-<pr_number>
WILDFLY_REPO=$WORKSPACE/wildfly
JBOSSWS_REPO=$WORKSPACE/jbossws-cxf
```

## Instructions

Execute the following steps in order. This is an INTERACTIVE workflow - prompt the user at each checkpoint before proceeding.

### Step 1: Check Upstream CI Checks

Determine if `gh` CLI is available by running `which gh` or `gh --version`.

If `gh` is available:
- Use `gh pr view <pr_number> --repo wildfly/wildfly --json statusCheckRollup` to get CI status
- Report: "Using GitHub CLI to check CI status"

Otherwise:
- Use GitHub API: `curl https://api.github.com/repos/wildfly/wildfly/pulls/<pr_number>/checks` - be aware of the actual repository where the PR is submitted, the `wildfly/wildfly` case covers the default use case, which should be close to the 100% of the cases.
- Or fetch the PR HTML page and parse the CI status section
- Report: "Using GitHub API" or "Using HTML parsing" (whichever you use)

Analyze the results:
- Are all checks green? → Report success and continue
- Are there failures?
  - Examine failure details
  - Determine if failures are related to the webservices changes
  - **Interactive Checkpoint**: "CI checks show failures: [list failures]. Do these appear related to the webservices upgrade? Options: (a) Unrelated, continue; (b) Related, stop and draft PR comment; (c) Investigate further"

If user chooses (b), draft a comment like:
```
The CI checks are showing failures that appear related to this upgrade:
[list relevant failures]

Could you please review these before proceeding?
```
Then STOP the skill execution.

### Step 2: Clone WildFly Repository

Derive the workspace paths from `pr_url`:

```bash
WORKSPACE=/tmp/wildfly-upgrade-<pr_number>
WILDFLY_REPO=$WORKSPACE/wildfly
JBOSSWS_REPO=$WORKSPACE/jbossws-cxf
```

**Existing-workspace check**: If `$WORKSPACE` already exists, prompt the user:
> "Found an existing workspace at $WORKSPACE. Reuse it or start fresh?"

- **Start fresh**: `rm -rf $WORKSPACE`, then proceed to clone both repos normally in their respective steps.
- **Reuse**: keep `$WORKSPACE` as-is. In this step and in Step 5, skip cloning any repo directory that already exists — handle partial reuse gracefully (e.g. WildFly was cloned but the run stopped before jbossws-cxf).

If `$WORKSPACE` does not exist, create it and proceed without prompting.

**Important**: Test against the main branch, not the PR branch directly. The PR branch may be stale compared to main.

Clone WildFly (skip if reusing and `$WILDFLY_REPO` already exists):
```bash
git clone --depth 1 https://github.com/wildfly/wildfly.git $WILDFLY_REPO
cd $WILDFLY_REPO
```

Apply the PR changes to main:
```bash
# Fetch the PR branch and find its commits
git fetch origin pull/<pr_number>/head:pr-<pr_number>
git log pr-<pr_number> --not main --oneline

# Cherry-pick the PR commits onto main
git cherry-pick <commit-sha>
...
```

Report the git status and show the applied changes with `git show HEAD --stat`.

**Interactive Checkpoint**: "WildFly main branch cloned and PR changes cherry-picked. Ready to analyze affected artifacts?"

### Step 3: Analyze Affected Artifacts

Fetch the PR diff using `gh pr diff <pr_number>` or GitHub API.

Parse the diff to identify:
1. Which POM files were modified
2. Which property versions changed (name and old→new value)
3. Which groupId:artifactId patterns are affected (cross-reference with .github/dependabot.yml webservices group)

Search the WildFly codebase to determine usage (runs against `$WILDFLY_REPO`):
- For each affected artifact, use `grep -r "groupId>artifact-group</groupId>" --include="pom.xml" $WILDFLY_REPO`
- Identify which modules/subsystems use these artifacts
- Classify: "Used exclusively by XML Web Services subsystem" vs "Used by WS and other components"

Create a summary like:
```
Affected artifacts:
- org.apache.cxf:cxf-core: 4.0.1 → 4.0.2
  Used by: webservices subsystem, testsuite/integration/ws
  Classification: WS-only

- org.glassfish.jaxb:jaxb-runtime: 4.0.6 → 4.0.8
  Used by: webservices, ee-feature-pack, multiple testsuites
  Classification: Broader usage (WS + EE platform)
```

Artifacts classified as "Broader usage (WS + other components)" will be used in Step 8 to
discover additional integration test submodules to run alongside `testsuite/integration/ws`.

**Interactive Checkpoint**: Present the summary and ask: "Does this change look legitimate from a high-level perspective? Proceed with testing?"
Stop the skill execution in case the user does not confirm, and suggest to conduct further investigation.

### Step 4: Quick Build WildFly

Execute from `$WILDFLY_REPO`:
```bash
cd $WILDFLY_REPO
mvn clean install -DskipTests
```

Monitor the build output. If build fails:
- Examine the error messages
- Check if it's a local configuration issue (offline mode, missing deps, etc.)
- **Interactive Checkpoint**: "Build failed with error: [error details]. CI is passing, so this may be a local issue. Options: (a) I'll fix it, retry; (b) Stop and draft PR comment; (c) Investigate"

If user chooses (b), draft a comment explaining the local build issue prevents validation.

On success, note the WildFly SNAPSHOT location (typically `$WILDFLY_REPO/dist/target/wildfly-<version>-SNAPSHOT/`).

### Step 5: Prepare jbossws-cxf Repository

Parse the WildFly POM (`$WILDFLY_REPO/pom.xml`) to find the jbossws-cxf version:
- Look for property matching `version.org.jboss.ws.cxf` or similar
- Extract the version value (e.g., "7.3.8.Final")

Clone jbossws-cxf at that tag (skip if reusing and `$JBOSSWS_REPO` already exists):
```bash
git clone --depth 1 --branch <version> https://github.com/jbossws/jbossws-cxf.git $JBOSSWS_REPO
cd $JBOSSWS_REPO
```

Report: "Cloned jbossws-cxf at tag <version> into $JBOSSWS_REPO"

**Interactive Checkpoint**: "jbossws-cxf prepared at tag <version>. Ready to build?"

### Step 6: Quick Build jbossws-cxf

Execute:
```bash
mvn clean install -DskipTests -Ptestsuite,dist -Dnodeploy
```

Report build status. If failures occur, follow same pattern as Step 4.

### Step 7: Run jbossws-cxf Tests

Construct the WildFly home path from Step 4 (should be `$WILDFLY_REPO/dist/target/wildfly-<version>-SNAPSHOT`).

Execute:
```bash
mvn verify -Dexclude-udp-tests -Dexclude-ws-discovery-tests -Dserver.home=<WILDFLY_HOME> -Ptestsuite,dist -Dnodeploy
```

Monitor and report:
- Total tests run
- Failures (if any)
- Error details for failed tests

**Interactive Checkpoint**: 
- If all tests pass: "✓ jbossws-cxf tests passed with the upgraded components. Continue?"
- If tests fail: "✗ jbossws-cxf tests failed: [summary]. Options: (a) Investigate and I'll provide resolution; (b) Appears unrelated, continue; (c) Stop and draft PR comment"

### Step 8: Run WildFly Integration Tests

**IMPORTANT**: This step must run BEFORE Step 9 (dependency alignment). If jbossws-cxf is rebuilt with aligned dependencies first, those artifacts are installed to the local .m2 repository and could contaminate these tests.

#### 8a. Discover additional integration test submodules

For each artifact classified in Step 3 as "Broader usage (WS + other components)", scan
`$WILDFLY_REPO/testsuite/integration/` for subdirectories whose `pom.xml` references that
artifact's groupId or artifactId:

```bash
grep -rl "<groupId>ARTIFACT_GROUP</groupId>\|<artifactId>ARTIFACT_ID</artifactId>" \
     $WILDFLY_REPO/testsuite/integration/*/pom.xml
```

Collect each matching subdirectory name (e.g., `basic`, `elytron`). `ws` is always included
and never duplicated even if the grep returns it.

#### 8b. Confirm submodule list with the user

Present the candidate list as paths relative to `$WILDFLY_REPO`:

```
Planned integration test submodules:
  testsuite/integration/ws          ← always included
  testsuite/integration/basic       ← org.glassfish.jaxb:jaxb-runtime found in pom.xml
  ...

Options:
  (a) Run with this list as-is
  (b) Remove one or more submodules (specify which)
  (c) Add submodules manually (specify paths)
  (d) Run ws only
```

Wait for the user's confirmation. Adjust the list according to any (b)/(c)/(d) response
before proceeding.

#### 8c. Execute tests

From `$WILDFLY_REPO`, build the comma-separated `-pl` argument from the confirmed list and
run a single Maven invocation:

```bash
cd $WILDFLY_REPO
mvn test -pl testsuite/integration/ws[,testsuite/integration/<module2>,...] --also-make
```

Monitor and report for each submodule:
- Total tests run
- Failures (if any)
- Error details for failed tests

**Interactive Checkpoint**:
- If all tests pass: "✓ WildFly integration tests passed for submodules: [confirmed list]. Continue to dependency alignment check?"
- If tests fail: "✗ WildFly integration tests failed in [submodule(s)]: [summary]. Options: (a) Investigate and I'll provide resolution; (b) Stop and draft PR comment"

### Step 9: Check jbossws-cxf Dependency Alignment

Parse the jbossws-cxf POM (typically at the root or in `modules/client/pom.xml` and similar):
- Look for dependencies matching the groupId:artifactId patterns from Step 2
- Compare versions with the upgrade target versions

If misalignment found:
- Report: "Found version mismatch in jbossws-cxf: [artifact] is at [old-version], upgrade target is [new-version]"
- **Interactive Checkpoint**: "Should I align jbossws-cxf dependency versions to match the upgrade target?"

If user agrees:
- Modify the jbossws-cxf POM(s) to update the property or version
- Re-execute Steps 6 and 7 (build and test)
- Report results
- Add note to final report: "Note: jbossws-cxf dependencies were aligned to match upgrade target"

**Interactive Checkpoint**: "Dependency alignment complete. Ready to create final report?"

### Step 10: Generate Final Report

Compile a comprehensive report with the following sections:

```
# WildFly XML Web Services Component Upgrade Validation Report

## PR Information
- PR: [PR URL]
- Title: [PR title]

## CI Status
✓/✗ [Status and method used to check]

## Affected Artifacts
[Summary from Step 2]

## Build Results
✓ WildFly build: SUCCESS
✓ jbossws-cxf build: SUCCESS

## Test Results

### jbossws-cxf Tests (Original Dependencies)
✓/✗ [Results from Step 7]
[Details if applicable]

### WildFly Integration Tests (Step 8)
Submodules run: [comma-separated list of actual submodules from Step 8]

✓/✗ [Per-submodule result summary]
[Details if applicable]

### jbossws-cxf Dependency Alignment
[Note if alignment was performed in Step 9]

### jbossws-cxf Tests (Aligned Dependencies)
✓/✗ [Results from Step 9 rebuild/retest, if performed]
[Details if applicable]

## Recommendation
✓ All tests passed. Safe to approve PR and create Jira issue.
OR
⚠ Tests passed with warnings: [details]
OR
✗ Blocking issues found: [details]

## Proposed PR Comment
[Draft appropriate comment based on results]
```

Present this report to the user.

### Step 11: Propose Jira Issues

**Important**: Create ONE Jira issue proposal PER upgraded component.

For each upgraded component identified in Step 2:

1. **Summary**: Use the PR title as a template, but make it specific to this component
   - Example: If PR title is "Bump webservices group dependencies", make it "Bump org.apache.cxf:cxf-core from 4.0.1 to 4.0.2"

2. **Description**: Construct URLs specific to this component:
   - Identify the GitHub repository for this artifact (e.g., org.apache.cxf → https://github.com/apache/cxf)
   - Construct Tag URL: `https://github.com/<org>/<repo>/releases/tag/<new-version>`
   - Construct Diff URL: `https://github.com/<org>/<repo>/compare/<old-version>...<new-version>`
   - Extract SHA: Use `git ls-remote https://github.com/<org>/<repo> refs/tags/<new-version>` or GitHub API

Present each Jira issue proposal separately:
```
Jira Issue Proposal #1:

Summary:
Bump org.apache.cxf:cxf-core from 4.0.1 to 4.0.2

Description:
Tag: https://github.com/apache/cxf/releases/tag/cxf-4.0.2
Diff: https://github.com/apache/cxf/compare/cxf-4.0.1...cxf-4.0.2
SHA: abc123def456

---

Jira Issue Proposal #2:

Summary:
Bump org.glassfish.jaxb:jaxb-runtime from 4.0.6 to 4.0.8

Description:
Tag: https://github.com/eclipse-ee4j/jaxb-ri/releases/tag/4.0.8
Diff: https://github.com/eclipse-ee4j/jaxb-ri/compare/4.0.6...4.0.8
SHA: def789ghi012
```

**Final Checkpoint**: "Validation complete. Review the report and Jira proposals (one per component). Should I draft the PR comment for you to post?"

## Error Handling

At any step, if an unexpected error occurs:
1. Report the error clearly
2. Provide context about which step failed
3. Ask user if they want to: (a) Retry; (b) Skip and continue; (c) Stop execution

## Notes

- This skill is INTERACTIVE - never proceed through checkpoints without user confirmation
- This skill does NOT modify WildFly code (only jbossws-cxf if alignment requested)
- This skill does NOT create Jira issues automatically
- This skill does NOT approve PRs automatically
- All outputs are proposals for user review and action

## Important Workflow Principles

### 1. Test Against Main Branch, Not PR Branch
The dependabot PR branch may be stale compared to main. Always:
- Clone the main branch fresh
- Cherry-pick the PR commit onto main
- Test against this updated main branch

This ensures validation against the most current codebase state.

### 2. Test Execution Order Matters
**WildFly WS Integration Tests (Step 8) MUST run BEFORE jbossws-cxf Dependency Alignment (Step 9)**

**Reason**: If jbossws-cxf is rebuilt with aligned dependencies first, those artifacts are installed to the local .m2 repository and could be picked up by WildFly tests, contaminating the validation.

**Correct sequence**:
1. Build jbossws-cxf with its original dependency versions (Step 6)
2. Test jbossws-cxf against upgraded WildFly (Step 7)
3. Test WildFly integration test submodules (Step 8) — `ws` always included; additional submodules determined by Step 3 artifact classification
4. THEN align jbossws-cxf dependencies and retest (Step 9)

This two-stage approach validates:
- Forward compatibility: upgraded WildFly works with current jbossws-cxf
- Dependency compatibility: aligned jbossws-cxf versions also work correctly

