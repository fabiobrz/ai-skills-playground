---
name: wildfly-upgrade-report-parser
description: >-
  Parse a "Possible component upgrades report - wildfly:main" HTML attachment,
  inspect WildFly module.xml files to find which JBoss modules depend on each
  candidate component, and emit a structured JSON catalogue of upgrade entries.
  Trigger: when asked to parse a WildFly component upgrade report, process a
  wildfly-dev upgrade-report attachment, or collect upgrade candidates from an
  HTML report.
license: Apache-2.0
compatibility: >-
  Requires git, grep, and either a local WildFly clone or internet access to
  clone one. Accepts a URL to the HTML attachment or a local file path.
args: report_url_or_path [wildfly_repo_path]
allowed-tools: >-
  Bash(command -v:*)
  Bash(curl --head:*)
  Bash(curl -fsSL:*)
  Bash(git clone:*)
  Bash(git rev-parse:*)
  Bash(git log:*)
  Bash(grep -r:*)
  Bash(grep -rl:*)
  Bash(grep -c:*)
  Bash(find:*)
metadata:
  author: fabiobrz
  version: "1.0"
  user-invocable: true
---

# WildFly Upgrade Report Parser

Parse the periodic "Possible component upgrades report - wildfly:main" HTML attachment,
discover which WildFly JBoss modules depend on each candidate component, and produce a
structured JSON catalogue that downstream skills (e.g. `wildfly-component-dependency-upgrade`)
can consume directly.

This skill uses the Agent Skill specification defined at: <https://agentskills.io/specification>

## Parameters

Parse the args string to extract:

- `report_url_or_path` (required): either a URL (HTTP/HTTPS) to the `attachment.html` file,
  or a local filesystem path to it.
- `wildfly_repo_path` (optional): path to an already-cloned WildFly repository. When omitted
  the skill clones `https://github.com/wildfly/wildfly.git` (depth 1) into a temporary
  directory derived from the report source.

```
REPORT_SOURCE=<url-or-path>
WILDFLY_REPO=<wildfly_repo_path>   # or /tmp/wildfly-upgrade-report-parser/wildfly if not supplied
```

## Non-negotiable safeguards

- Never delete, modify, or commit files inside the WildFly repository.
- Never push to any remote.
- Never create Jira issues or GitHub PRs.
- When a URL is provided, download with `curl`; never execute the downloaded content.
- Emit all structured output as valid JSON. If a field cannot be determined, set it to `null`.

## Workflow

### Step 1: Verify prerequisites and resolve inputs

1. Check `command -v git` and `command -v grep` succeed. If either is missing, stop and
   report what is unavailable.
2. If `report_url_or_path` is a URL (`http://` or `https://`), verify it is reachable:
   ```bash
   curl --head -fsS "<url>" -o /dev/null
   ```
   If unreachable, stop and report the HTTP status or connection error.
3. Determine `WILDFLY_REPO`:
   - If `wildfly_repo_path` was supplied, verify `git rev-parse --show-toplevel` succeeds
     inside it and that it is a WildFly repository (check for `pom.xml` with
     `<artifactId>wildfly-parent</artifactId>` or similar).
   - If not supplied, set `WILDFLY_REPO=/tmp/wildfly-upgrade-report-parser/wildfly`.
   - If the path does not exist yet, mark it for cloning in Step 2.
   - If the path already exists and is a valid WildFly clone, reuse it and skip cloning.

Report the resolved paths before continuing.

### Step 2: Clone WildFly (if needed)

If `WILDFLY_REPO` was marked for cloning:

```bash
mkdir -p "$(dirname "$WILDFLY_REPO")"
git clone --depth 1 https://github.com/wildfly/wildfly.git "$WILDFLY_REPO"
```

Report the cloned commit (`git log -1 --oneline` inside `$WILDFLY_REPO`).

### Step 3: Obtain and parse the HTML report

If `report_url_or_path` is a URL, download it:

```bash
curl -fsSL "<url>" -o /tmp/wildfly-upgrade-report-parser/attachment.html
```

Otherwise use the supplied local path directly.

Parse every upgrade candidate entry from the HTML. The report is produced by the WildFly
build infrastructure and each entry typically contains:

- **Component / artifact** – groupId:artifactId (or display name)
- **Current version** – the version currently bundled in WildFly
- **Proposed version** – the newer version suggested by the report
- **Maven property** – the POM property controlling the version (when present, e.g.
  `version.commons-codec`)
- Any additional metadata columns present (URL, licence, etc.)

Parse ALL entries — do not stop after the first one.

Produce an internal list `CANDIDATES[]` where each element holds the raw parsed fields.
If a field cannot be found for a given row, set it to `null`.

### Step 4: Discover dependent WildFly modules

For every candidate in `CANDIDATES[]`, determine which JBoss modules reference it.

The search strategy follows the established WildFly convention:

1. **Identify search terms**: derive one or more short, distinctive tokens from the
   `artifactId` or the Maven property name. For example, for `commons-codec` the tokens
   would be `codec` and `commons`. Use the minimum set that avoids false positives while
   still catching the relevant `module.xml` files.

2. **Run `git grep` over `module.xml` files** inside `$WILDFLY_REPO`:

   ```bash
   # Discover module.xml files that reference the artifact
   git -C "$WILDFLY_REPO" grep -l "<token1>" -- "*/module.xml" \
     | xargs grep -l "<token2>"
   ```

   Adjust the pipeline for one token or more than two tokens as needed.

3. **Collect matching paths** relative to `$WILDFLY_REPO`. These are the JBoss module
   definition files that contain a direct reference to the component.

4. **Extract the JBoss module names** from each matched `module.xml` by reading the
   `name` attribute of the root `<module>` element:

   ```bash
   grep -o 'name="[^"]*"' <path>/module.xml | head -1
   ```

5. **Classify** each found module:
   - `"direct"` – the module's `<artifact>` element references this component (the module
     *ships* the JAR).
   - `"dependent"` – the module's `<module>` dependency list references this component
     (the module *uses* the JAR that another module ships).

   Use `grep -c '<artifact'` vs `grep -c '<module name'` within each matched file to
   distinguish the two; a file can be both (ships it and declares it as a dep of itself
   is unusual but handle it by recording both).

Populate each candidate with its `affected_modules` list.

### Step 5: Emit the JSON catalogue

Output a single JSON object to stdout:

```json
{
  "source": "<report_url_or_path>",
  "wildfly_repo": "<WILDFLY_REPO>",
  "wildfly_commit": "<git log -1 --format=%H>",
  "generated_at": "<ISO-8601 timestamp>",
  "entries": [
    {
      "component": "<display name or groupId:artifactId>",
      "group_id": "<groupId or null>",
      "artifact_id": "<artifactId or null>",
      "maven_property": "<POM version property or null>",
      "current_version": "<version currently in WildFly>",
      "proposed_version": "<version suggested by the report>",
      "report_url": "<per-entry upstream URL from the report, or null>",
      "affected_modules": [
        {
          "module_name": "<JBoss module name, e.g. org.apache.commons.codec>",
          "module_xml_path": "<path relative to WILDFLY_REPO>",
          "classification": "direct | dependent"
        }
      ]
    }
  ]
}
```

Write the JSON to `/tmp/wildfly-upgrade-report-parser/upgrade-candidates.json` and also
print it to stdout so agents invoking this skill can capture it directly.

Also print a compact human-readable summary table:

```
=== WildFly Upgrade Candidates ===
Repo:   <WILDFLY_REPO> @ <short commit SHA>
Report: <report_url_or_path>
Parsed: <ISO-8601 timestamp>

#  Component                        Current    Proposed   Modules
─────────────────────────────────────────────────────────────────────
1  commons-codec:commons-codec      1.15       1.17.1     3 affected
2  io.netty:netty-codec             4.1.100    4.1.115    5 affected
...

Full JSON written to /tmp/wildfly-upgrade-report-parser/upgrade-candidates.json
```

### Step 6: Report completion

State:
- Total number of candidates parsed from the report.
- Total number of unique JBoss modules found across all entries.
- Path to the written JSON file.
- If any candidate returned zero `affected_modules`, list those component names explicitly
  as a warning — they may still be relevant but could not be located via module search.

Do not start any upgrade validation. Downstream invocation of
`wildfly-component-dependency-upgrade` or a similar skill is left to the caller.

## Error handling

At any step, if an unexpected error occurs:
1. Report the step name, the failed command, and the exact error output.
2. For non-fatal issues (e.g. a single candidate fails module discovery), record
   `"affected_modules": []` for that entry, emit a warning, and continue processing the
   remaining candidates.
3. For fatal issues (prerequisites missing, report unparseable, WildFly clone failed),
   stop immediately and report what must be resolved before retrying.

## Notes

- This skill is **read-only** with respect to both the WildFly repository and any remote
  services. It clones, greps, and reads — nothing else.
- The JSON output is designed to be consumed directly by `wildfly-component-dependency-upgrade`
  or a future orchestrator skill. The `maven_property` field is particularly important for
  locating the exact line to change in the WildFly POM.
- When `wildfly_repo_path` is supplied by the caller (e.g. an orchestrator that already
  cloned WildFly for other purposes), no additional clone is performed and the two skills
  share the same workspace — pass the same path to both.
