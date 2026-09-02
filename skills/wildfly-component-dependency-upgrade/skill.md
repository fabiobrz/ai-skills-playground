---
name: webservices-dependency-upgrade
description: Test and validate WildFly XML Web Services component dependency upgrades from dependabot PRs
args: pr_url wildfly_path jbossws_path
---

# WildFly XML Web Services Component Upgrade Validation

You are executing a skill to validate Web Services component dependency upgrades in WildFly. 
This workflow tests dependabot PRs that update dependencies in the webservices group (see .github/dependabot.yml).

## Parameters

Parse the args string to extract:
- `pr_url` (required): PR URL or PR number (assume wildfly/wildfly if just a number)
- `wildfly_path` (required): Path to local WildFly repo (prompt user if not provided)
- `jbossws_path` (required): Path to local jbossws-cxf repo (prompt user if not provided)

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

### Step 2: Analyze Affected Artifacts

Fetch the PR diff using `gh pr diff <pr_number>` or GitHub API.

Parse the diff to identify:
1. Which POM files were modified
2. Which property versions changed (name and old→new value)
3. Which groupId:artifactId patterns are affected (cross-reference with .github/dependabot.yml webservices group)

Search the WildFly codebase to determine usage:
- For each affected artifact, use `grep -r "groupId>artifact-group</groupId>" --include="pom.xml"` 
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

**Interactive Checkpoint**: Present the summary and ask: "Does this change look legitimate from a high-level perspective? Proceed with testing?"
Stop the skill execution in case the user does not confirm, and suggest to conduct further investigation.

### Step 3: Prepare WildFly Repository

Navigate to the WildFly repo path:
- `cd` to `wildfly_path`

**Important**: Test against the main branch, not the PR branch directly. The PR branch may be stale compared to main.

Execute:
```bash
git fetch upstream
git pull upstream main
```

Apply the PR changes to main:
```bash
# Find the PR commit
git log <pr_branch> --not main --oneline

# Cherry-pick the PR commits onto main
git cherry-pick <commit-sha>
...
```

Report the git status and show the applied changes with `git show HEAD --stat`.

**Interactive Checkpoint**: "WildFly main branch updated with PR changes cherry-picked. Ready to build?"

### Step 4: Quick Build WildFly

Execute:
```bash
mvn clean install -DskipTests
```

Monitor the build output. If build fails:
- Examine the error messages
- Check if it's a local configuration issue (offline mode, missing deps, etc.)
- **Interactive Checkpoint**: "Build failed with error: [error details]. CI is passing, so this may be a local issue. Options: (a) I'll fix it, retry; (b) Stop and draft PR comment; (c) Investigate"

If user chooses (b), draft a comment explaining the local build issue prevents validation.

On success, note the WildFly SNAPSHOT location (typically `dist/target/wildfly-<version>-SNAPSHOT/`).

### Step 5: Prepare jbossws-cxf Repository

Parse the WildFly POM to find the jbossws-cxf version:
- Look for property matching `version.org.jboss.ws.cxf` or similar
- Extract the version value (e.g., "7.3.8.Final")

Navigate to the local jbossws-cxf path:
- `cd` to `jbossws_path`

Checkout the tag used by WildFly:
```bash
git fetch --tags
git checkout tags/<version>
```

Report: "Checked out jbossws-cxf version <version>"

**Interactive Checkpoint**: "jbossws-cxf prepared at tag <version>. Ready to build?"

### Step 6: Quick Build jbossws-cxf

Execute:
```bash
mvn clean install -DskipTests -Ptestsuite,dist -Dnodeploy
```

Report build status. If failures occur, follow same pattern as Step 4.

### Step 7: Run jbossws-cxf Tests

Construct the WildFly home path from Step 4 (should be `<wildfly_repo>/dist/target/wildfly-<version>-SNAPSHOT`).

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

### Step 8: Run WildFly WS Integration Tests

**IMPORTANT**: This step must run BEFORE Step 9 (dependency alignment). If jbossws-cxf is rebuilt with aligned dependencies first, those artifacts are installed to local .m2 repository and could contaminate these tests.

Change directory:
```bash
cd <wildfly_repo>/testsuite/integration/ws
```

Execute:
```bash
mvn test
```

Monitor and report:
- Total tests run
- Failures (if any)
- Error details for failed tests

**Interactive Checkpoint**:
- If all tests pass: "✓ WildFly WS integration tests passed. Continue to dependency alignment check?"
- If tests fail: "✗ WildFly WS integration tests failed: [summary]. Options: (a) Investigate and I'll provide resolution; (b) Stop and draft PR comment"

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

### WildFly WS Integration Tests
✓/✗ [Results from Step 8]
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
- Pull latest main branch
- Cherry-pick the PR commit onto main
- Test against this updated main branch

This ensures validation against the most current codebase state.

### 2. Test Execution Order Matters
**WildFly WS Integration Tests (Step 8) MUST run BEFORE jbossws-cxf Dependency Alignment (Step 9)**

**Reason**: If jbossws-cxf is rebuilt with aligned dependencies first, those artifacts are installed to the local .m2 repository and could be picked up by WildFly tests, contaminating the validation.

**Correct sequence**:
1. Build jbossws-cxf with its original dependency versions (Step 6)
2. Test jbossws-cxf against upgraded WildFly (Step 7)
3. Test WildFly WS integration suite (Step 8)
4. THEN align jbossws-cxf dependencies and retest (Step 9)

This two-stage approach validates:
- Forward compatibility: upgraded WildFly works with current jbossws-cxf
- Dependency compatibility: aligned jbossws-cxf versions also work correctly

