---
name: draft-security-advisory
description: >-
  Draft evidence-based GitHub security advisories from public CVE records and optional Jira fixes.
  Trigger: when asked to prepare, review, or populate an advisory, CVE description, or proof of concept.
license: Apache-2.0
metadata:
  author: yborgess
  version: "1.0.0"
  user-invocable: true
---

# Draft Security Advisory

Prepare accurate, ready-to-paste GitHub Security Advisory fields from public CVE information and, when available, the Jira issue, code change, and tests for the fix. Draft only unless the user explicitly asks for another action.

## When to Use

- The user provides a public CVE and asks for an advisory draft or help filling GitHub's advisory form.
- The user provides or asks to find the Jira issue, pull request, commit, or regression test associated with the fix.
- The user asks whether a safe, supportable reproducer can be derived from the public record and fix.

## Workflow

### 1. Establish authoritative facts

1. Confirm the CVE identifier and retrieve its public CVE/CNA record and the affected product vendor's advisory. Use other databases for discovery or context, not as a substitute for primary sources. Open sources rather than relying on search-result snippets.
2. Record the source and confidence for each fact: weakness/CWE, vulnerable component and code path, attacker prerequisites, impact, affected products and versions, fixed versions, and published severity/CVSS vector.
3. Treat a vendor's product-specific affected-version and severity information as authoritative for that vendor's products. Do not infer upstream version ranges from a downstream product listing or invent a fixed version.
4. Explicitly mark facts as unknown or conflicting when the sources do not establish them. Do not turn absence of information into a claim that a product is unaffected or that exploitation is impossible.

### 2. Correlate the Jira fix and code, if available

1. If the user supplies a Jira key or URL, retrieve that issue. If none is supplied and Atlassian tools are available, search for the exact CVE identifier and relevant product/component. If results are ambiguous, show the likely candidates and ask which one to use.
2. Read the issue's linked commits, pull requests, and regression tests when accessible. Inspect repository code or public changes read-only. Identify what the fix changes and what test demonstrates the corrected behavior.
3. Keep Jira content separate from public advisory text. Jira may contain non-public details: do not quote or expose internal comments, people, credentials, internal URLs, or other sensitive information in a public draft. Use the issue to understand the fix, and cite only public references in the advisory unless the user confirms a reference is public and appropriate.
4. If the issue or patch cannot be accessed, say so and continue using verified public sources; do not imply that the fix was inspected.

### 3. Assess a reproducer

1. Look for an existing regression test, documented trigger, and the smallest affected code path. A test that only proves the fixed behavior is not by itself proof that the vulnerable behavior was reproduced.
2. When the evidence supports it, draft a minimal reproducer, usually as precise test steps or a focused regression test. Base API names, setup, and expected results on inspected code/tests; do not invent runnable commands or signatures.
3. Label the result accurately:
   - **Verified:** executed against a named affected version in an isolated environment, with the observed result recorded.
   - **Unverified candidate:** derived from the issue, patch, or tests, but not executed. Say what remains to validate.
   - **Unavailable:** the available evidence is insufficient to create safe, reliable reproduction steps. Explain the specific limitation.
4. Do not execute a reproducer or modify repository files unless the user explicitly asks. Before an authorized run, establish a disposable, isolated test environment. For filesystem or state-changing behavior, confine every operation to a temporary sandbox; never target production, real credentials, or host paths outside that sandbox.
5. Do not describe general preparation advice as a proof of concept. If no verified PoC is available, provide a truthful explanation of its status rather than fabricated steps or results.

### 4. Draft the GitHub fields

Keep these fields distinct. Some overlap is unavoidable, but avoid repeating the same paragraph in each:

| Field | Put this here |
| --- | --- |
| **Summary** | A short headline naming the flaw and its principal consequence. Make the impact clear; the CVE ID is already entered separately when applicable. |
| **Details** | The technical root cause, affected component/code path, and how the vulnerable input or operation reaches it. State only verified prerequisites. |
| **Proof of concept** | Verified reproduction steps and observed result, or a clearly labeled unverified candidate. Include setup, exact operation, and expected vulnerable versus fixed behavior where known. |
| **Impact** | What an attacker can achieve and who is exposed, including required access/role and product or configuration conditions. Describe confidentiality, integrity, or availability consequences only when supported by evidence. |

The GitHub form in the user's current workflow requires at least **150 characters** in the Proof of concept field. Check the final field length. If no verified reproducer is available, use a tailored, accurate status explanation of at least 150 characters; state what evidence was reviewed and why reproduction is not verified. A suitable starting point, only when true, is:

> Verified reproduction steps are not available for this advisory. The public CVE information and fix evidence reviewed do not establish a complete, safe sequence that has been confirmed against an affected version. Any proposed reproducer should be validated in an isolated, disposable test environment before it is described as working.

Do not use that fallback if it misstates what was reviewed or why validation is unavailable. Do not fill the field with generic setup instructions and present them as a reproducer.

### 5. Return a reviewable draft

Present:

1. The four fields as separate, ready-to-paste sections.
2. Reproducer status (verified, unverified candidate, or unavailable) and what evidence supports that status.
3. Confirmed CWE, affected/fixed versions, published severity/CVSS, and public references when available. Keep version and score claims out of the draft if they have not been confirmed.
4. A short list of unresolved questions or conflicting source claims.

Keep internal Jira findings clearly separate from public text. Do not include a private Jira link in the public reference list.

## Safety and Scope

- Drafting does not authorize publishing a GitHub advisory, editing Jira, committing code, changing repository files, or executing tests. Ask for explicit authorization for those actions.
- Do not claim a test was run, a fix was inspected, a version is affected, or a vulnerability is exploitable unless the evidence supports the claim.
- Do not upgrade a published severity rating or change a CVSS vector based on speculation. Attribute scores to their source when multiple sources differ.
- Ask for clarification when the target product/repository, public disclosure scope, or intended advisory audience is unclear.

## Commands

For read-only inspection of a supplied local fix commit:

```bash
git -C <repository> show --stat --oneline <fix-commit>
git -C <repository> show --format= --no-ext-diff <fix-commit>
```

Use the repository's documented test command only after the user asks to run tests and the environment is isolated.

## Example

User: “Draft a GitHub advisory for CVE-YYYY-NNNN. Find the Jira fix, inspect its tests, and propose a reproducer if the evidence supports one. Do not publish or modify the repository.”
