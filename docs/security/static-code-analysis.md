# Static code analysis

How this codebase is scanned for security defects, what blocks a merge, how a finding
is dispositioned, and where the evidence is kept.

Status markers below distinguish what is **in place** from what is **pending** — this
document is written to be read by an assessor, so nothing aspirational is described in
the present tense.

## 1. Tool inventory

### Source code analysis (SAST)

| Tool | Version | Language surface | Ruleset |
|---|---|---|---|
| Brakeman | 8.0.4 | Ruby / Rails — the `app/` Rails application | All 79 default checks. No `--skip-checks`, no `.brakeman.yml`; the only tuning is the suppression register at `app/config/brakeman.ignore`. |
| RuboCop | 1.81.7 | Ruby | `rubocop-rails-omakase` + `rubocop-rspec`. Style and correctness — **not a security ruleset**; it is listed for completeness, not as a security control. |
| ERB Lint | 0.9.0 | ERB templates | Project default (`.erb_lint.yml`) |
| CodeQL | GitHub-hosted, **default setup** (configured in repository settings, not in this repo) | Six languages, auto-detected — see coverage table below | Query suite is set in Settings → Code security; not visible from the repository. |

**CodeQL default setup coverage** (Security → Code scanning → Tools):

| Language | Files scanned | Coverage |
|---|---|---|
| GitHub Actions | 39/39 | 100% |
| JavaScript | 57/57 | 100% |
| TypeScript | 15/15 | 100% |
| Python | 4/4 | 100% |
| Ruby | 469/473 | 99% |
| Go | 1/2 | 50% |

Two things follow from this that are easy to miss. **CodeQL scans Ruby as well as
Brakeman does** — the two overlap on the Rails codebase and find different classes of
defect, so neither replaces the other. And the JavaScript figure (57 files) exceeds the
30 `.js` files under `app/app/javascript`, because default setup also scans the 27 test
files under `app/spec/javascript`.

Prettier formats JavaScript but performs no security analysis; it is not a security
control.

CodeQL is configured through **default setup**, enabled in repository settings. Because
only one of default setup and advanced setup can be active, a committed advanced-setup
workflow analyzes successfully but has its results rejected on upload with *"CodeQL
analyses from advanced configurations cannot be processed when the default setup is
enabled."* Do not add one without first disabling default setup.

Results land in Security → Code scanning, whose summary view requires write access.
Be aware that on a public repository, code scanning **annotations on pull requests are
visible to anyone with read access**, so an unremediated finding is publicly visible on
the PR that introduced it.

Versions are pinned in `app/Gemfile.lock` and move only via Dependabot PRs, so the
version recorded in an archived report is authoritative for that scan.

### Adjacent scanning (not source SAST, listed for scope clarity)

| Tool | Target |
|---|---|
| Trivy, Grype, Dockle, Hadolint | Container images and Dockerfiles |
| Checkov, tfsec | Terraform (`infra/`) — see `docs/compliance.md` |
| OWASP ZAP | Running application (DAST). Manual `workflow_dispatch` only — not continuous. |

## 2. Triggers

Brakeman runs from `.github/workflows/brakeman-analysis.yml`:

| Trigger | Scope | Evidence role |
|---|---|---|
| `pull_request` → `main` | paths `app/**` | **Newly developed code is scanned before merge.** Every change to application code is analyzed while it is still a proposal. |
| `push` → `main` | paths `app/**` | Post-merge confirmation of the integrated state. |
| `schedule` — Mondays 12:00 UTC | whole default branch | **Proof of continuous operation.** Runs regardless of commit activity, so a quiet week still produces a dated report, and a newly added Brakeman check surfaces against existing code. |

CodeQL runs from `.github/workflows/codeql.yml` on the same three trigger types, with
`paths` scoped to `app/app/javascript/**` and the weekly scan at Mondays 13:00 UTC —
an hour after Brakeman, so the two produce independent continuity evidence. It is
configured as CodeQL **advanced setup** (a committed workflow) rather than default
setup, which requires repository admin.

The `paths: ['app/**']` filter does not create a coverage gap: Brakeman analyzes only
the Rails application, so a change outside `app/**` is outside its analysis surface.

> **Status — known continuity gap.** The Brakeman Scan workflow was found **disabled**
> in the Actions UI on 2026-08-11 and has been re-enabled. A disabled workflow is
> disabled repository-wide and for all triggers, so for the duration of that period
> there were no PR scans, no post-merge scans, and no weekly scheduled scans — the
> continuous-operation evidence described above has a hole in it, and the gating
> policy in section 3 was not in force because no check was produced at all. The start
> of the gap has not yet been established; it can be bounded by the date of the last
> `Brakeman Scan` run in the Actions tab. See Open items #8.

## 3. Gating policy

**A non-zero Brakeman exit blocks the merge.** The scan step is:

```bash
bundle exec brakeman . --ensure-ignore-notes --ensure-no-obsolete-ignore-entries
```

| Exit | Meaning | Result |
|---|---|---|
| 0 | Clean | Check passes |
| 3 | An unsuppressed warning exists | Check fails |
| 8 | A suppression entry has no justification | Check fails |
| 9 | A suppression entry no longer matches any warning | Check fails |

There is no severity or confidence threshold in the gate: *any* unsuppressed warning
fails the build. A finding is therefore either fixed or explicitly dispositioned
(section 4) before code reaches `main`. This is what keeps `main` at zero warnings
as a steady state rather than a periodic cleanup target.

**Status — requires confirmation.** The workflow fails correctly, but a failing check
only *blocks* a merge if `Brakeman Scan` is configured as a required status check in
branch protection for `main`. That setting is not visible in the repository and has
not been verified. Confirm in Settings → Branches before citing this section as an
implemented control.

Note also that the two evidence-publishing steps carry `continue-on-error: true`
(see section 6) — a failure to archive does not currently fail the build. That is a
deliberate, temporary rollout allowance, not part of the gating policy.

**CodeQL is not a merge gate.** `github/codeql-action/analyze` uploads results to code
scanning and succeeds whether or not it finds anything; it has no equivalent of
Brakeman's non-zero exit. Blocking merges on CodeQL findings requires either code
scanning merge protection or a required check, both of which are repository settings
and neither of which is configured. CodeQL findings are therefore reviewed through the
Security → Code scanning tab and triaged under section 5, not enforced at merge time.

## 4. Suppression process

Suppressions are recorded in `app/config/brakeman.ignore` — the suppression register.
It is the authoritative list of findings reviewed and consciously not fixed. It is not
a noise filter.

**Every entry must carry, in its `note` field:**

1. **A justification** — why the finding is not exploitable: what the flagged code does,
   where the untrusted-looking input actually originates, and what guards it. Each note
   stands alone and must not refer the reader to another entry.
2. **A ticket number** — the ticket where the disposition was analyzed and agreed.

A justification answers *"why is this safe?"*, never *"why is this inconvenient to
fix?"*. If the honest answer is the latter, the finding is remediated or tracked as
work, not suppressed.

**Approver.** A suppression is approved by review and merge of the pull request that
adds it. The PR is the approval record; there is no separate sign-off artifact.
Suppressions must be raised in a PR a reviewer can evaluate on its own terms — never
folded into an unrelated change. Designated approvers are the project code owners:
Patricia Perozo (@pperozo), Clé Diggins (@cdigg), Jeff Catania (@jeffcatania).

> **Status — policy, not mechanism.** `CODEOWNERS.md` is documentation. GitHub only
> reads `CODEOWNERS`, `.github/CODEOWNERS`, or `docs/CODEOWNERS`, none of which exist
> in this repository, so code-owner review is **not automatically requested or
> enforced**. Adding a real CODEOWNERS file would make this control mechanical.

**Machine-enforced.** `--ensure-ignore-notes` fails the build (exit 8) if any entry has
an empty note. A ticket number cannot be enforced by Brakeman — `note` is free text —
so that half is upheld in code review.

**Pruning.** When suppressed code is fixed or removed, its entry becomes obsolete and
must be deleted; a stale entry can silently suppress a future real finding. The JSON
report's top-level `obsolete` array names the offending fingerprints:

```bash
cd app
bundle exec brakeman . -f json --no-exit-on-warn \
  | ruby -rjson -e 'puts JSON.parse($stdin.read)["obsolete"]'
```

`--ensure-no-obsolete-ignore-entries` fails the build (exit 9) if any remain, so the
register cannot drift.

Entries are matched by `fingerprint`, a stable hash of the warning's identity that
survives line-number changes. The `file` and `line` fields in an entry are
informational and may go stale harmlessly.

## 5. Remediation expectations

**Brakeman confidence is not severity.** Confidence expresses how certain Brakeman is
that its pattern matched — not how damaging the defect would be. A High-confidence
finding in a non-production-only controller may carry no risk; a Weak-confidence
finding on the transmission path may be critical. Treating confidence as severity
produces exactly the wrong prioritization.

So the two are separated: **confidence sets how quickly a finding must be triaged;
assessed severity sets how quickly it must be remediated.**

### Triage — driven by Brakeman confidence

| Confidence | Triage within | Outcome of triage |
|---|---|---|
| High | 1 business day | Assign a severity, then fix or suppress with justification |
| Medium | 5 business days | Assign a severity, then fix or suppress with justification |
| Weak | Next weekly review | Assign a severity, then fix or suppress with justification |

### Remediation — driven by assessed severity

Severity is assigned at triage from the CWE, the reachability of the code path, and
whether the affected route is reachable in production.

| Assessed severity | Remediate within |
|---|---|
| High | 30 days |
| Moderate | 90 days |
| Low | 180 days |

> **Status — PROPOSED, requires sign-off.** These windows follow the conventional
> FedRAMP / GovRAMP POA&M timelines. No remediation SLA previously existed in this
> repository (there is no `SECURITY.md` or equivalent), so these are a starting
> proposal, not an inherited standard. Confirm against the control matrix and adjust.

**In practice the gate does most of the work.** Because any unsuppressed warning fails
the build (section 3), a finding introduced by a pull request cannot linger — it is
resolved before merge. These SLAs therefore principally govern findings that appear
*without* a code change: those surfaced by the weekly scheduled scan, or by a Brakeman
upgrade that adds new checks.

## 6. Evidence capture and retention

Each scan emits a machine-readable report that is archived immutably, so the security
posture of any given commit can be reconstructed after the fact.

**What is captured.** `brakeman -f json` produces a report whose `scan_info` already
records `brakeman_version`, `ruby_version`, `rails_version`, start and end timestamps,
duration, the full list of all 79 checks performed, and object counts (controllers,
models, templates). `.github/scripts/enrich_brakeman_report.rb` then adds the
provenance only GitHub knows:

| Field | Purpose |
|---|---|
| `commit_sha` | Exact code state scanned |
| `ref` | Branch scanned |
| `repository` | Source repository |
| `workflow_run_url` | Link back to the run's logs |
| `run_attempt` | Distinguishes re-runs of the same commit |

The report is generated **before** the gate and published regardless of outcome — a
scan that finds warnings is precisely the evidence worth keeping.

**Where it goes.** `s3://dpw-iv-cbv-payroll-security-scan-reports/brakeman/YYYY/MM/DD/<commit-sha>/run-<run-id>-attempt-<n>.json`,
keyed by date and commit SHA. PR-run reports are not archived: they are not the audit
record, and pull requests from forks cannot assume the OIDC role.

**Why not GitHub Actions artifacts.** Artifact retention is capped at 90 days on public
repositories, below any plausible AU-11 window. Retention and immutability are
therefore properties of the bucket, not of CI.

**Bucket controls** (`infra/app/security-scan-reports/`):

| Control | Setting |
|---|---|
| Versioning | Enabled |
| Object Lock | Enabled, **COMPLIANCE** mode — no principal, including the account root, can delete or overwrite a version before its retention expires |
| Encryption | AES256 at rest |
| Transport | TLS required by bucket policy |
| Public access | Blocked |

**Lifecycle.** Retention is enforced by lifecycle rules, never manual deletion, so the
schedule is self-documenting:

| Phase | Age | Storage class |
|---|---|---|
| Hot | 0–90 days | S3 Standard — matches the AU-11 "online" anchor |
| Archive | 90 days – expiry | Glacier Instant Retrieval — retrieval stays immediate for assessors |
| Expiration | `expiration_days` (default 1095 / 3 years) | Deleted |

> **Status — not yet operational.** The bucket does not exist. It is created by a
> manual `make infra-update-app-security-scan-reports APP_NAME=app`, and
> `object_lock_retention_days` has no default and must be set deliberately, because
> Object Lock retention can be increased later but never decreased. Until the bucket
> is applied, the publish steps carry `continue-on-error: true` so they do not take
> `main` red; **both must be removed once the bucket exists**, otherwise a silently
> broken archive reads as a passing build.

### CodeQL evidence is not archived

The retention story above covers Brakeman only. **CodeQL results are not captured into
the S3 archive**, and the difference is structural, not an oversight of configuration:

| | Brakeman | CodeQL (default setup) |
|---|---|---|
| Artifact we control | JSON report, written by our workflow | None — results go straight to GitHub |
| Storage | Our S3 bucket | GitHub's code scanning service |
| Immutability | Object Lock, COMPLIANCE mode | None — alerts can be dismissed by anyone with write access, and analyses deleted via the REST API |
| Retention set by | Us (`expiration_days`) | GitHub, and subject to change by GitHub |
| Survives repository deletion | Yes | No |

GitHub's published retention keeps open alerts for the life of the account and closed
alerts fully accessible for two years before moving them to full-fidelity archival
storage. That is generous, but it is GitHub's policy to revise — a June 2026 changelog
announced exactly such a revision for Dependabot alerts, with the timing for other alert
types still being finalized — and it provides no immutability guarantee.

For AU-11 parity, CodeQL results would need to be exported on a schedule and written to
the same bucket under a `codeql/` prefix. Default setup produces no SARIF we can
intercept, but the REST API exposes both the analysis list and the SARIF itself:

```
GET /repos/{owner}/{repo}/code-scanning/analyses
GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}   Accept: application/sarif+json
GET /repos/{owner}/{repo}/code-scanning/alerts
```

A scheduled workflow with `security-events: read` could archive these alongside the
Brakeman reports. Not implemented — see Open items.

## Open items

| # | Item | Blocking |
|---|---|---|
| 1 | AU-11 retention window — the control matrix value that sets `object_lock_retention_days` and `expiration_days`. GovRAMP inherits NIST 800-53 Rev 5, where AU-11 is an organization-defined parameter; there is no number to adopt without the matrix. | First `terraform apply` |
| 2 | Confirm `Brakeman Scan` is a required status check on `main` (section 3) | Citing the gate as an implemented control |
| 3 | Sign off or adjust the remediation SLAs (section 5) | Citing section 5 as policy |
| 4 | Apply the bucket, then remove both `continue-on-error: true` lines (section 6) | Evidence capture becoming operational |
| 5 | Record CodeQL default setup's **query suite** (Default vs Extended) in section 1 — it is set in repository settings and cannot be read from the repo. Extended finds more at some cost in precision. | An accurate ruleset column |
| 5b | Create a task to enable code scanning merge protection for CodeQL — Settings → Rules → Rulesets → branch ruleset on `main` → Code scanning → tool `CodeQL`, with alert and security-alert thresholds. Requires admin. Note default setup's own check is not a gate on its own. | Gating parity with Brakeman |
| 5c | Investigate CodeQL's Go coverage (1/2 files) and Ruby (469/473). Small gaps, but an assessor will ask what the unscanned files are. | Complete coverage claim |
| 7 | **CodeQL evidence is not archived** (section 6). Results live only in GitHub, under GitHub's retention and with no immutability. Decide whether to build the scheduled REST-API export to S3, or to accept and document GitHub-held retention as sufficient. | AU-11 parity across both scanners |
| 8 | **Establish the Brakeman continuity gap** (section 2). The workflow was found disabled on 2026-08-11 and re-enabled. Record the date of the last run before that from the Actions tab, then state the gap explicitly in sections 2 and 3 rather than leaving both describing controls that were not operating. Consider whether anything merged during the gap needs a retrospective scan. | Truthful continuity and gating claims |
| 6 | Add a functional `CODEOWNERS` file so approver review is enforced, not merely documented (section 4) | Mechanical approval control |
