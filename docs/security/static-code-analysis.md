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

CodeQL is configured through **default setup**, enabled in repository settings.

Results land in Security → Code scanning, whose summary view requires write access.
Be aware that on a public repository, code scanning **annotations on pull requests are
visible to anyone with read access**, so an unremediated finding is publicly visible on
the PR that introduced it.

Scanner versions are pinned exactly in `app/Gemfile.lock`, and CI installs with Bundler
in deployment mode, which installs precisely those versions and fails if the lockfile is
out of sync with the Gemfile. The version therefore cannot drift between runs or between
a developer machine and CI, and the `brakeman_version` recorded in an archived report is
authoritative for that scan.

Changing a scanner version requires a reviewed commit to `Gemfile.lock`. Dependabot
raises those PRs weekly for direct dependencies (`.github/dependabot.yml`, with major
bumps to `rails`, `puma`, and `ruby` excluded), but versions are also bumped by hand when
a vulnerability needs clearing — so Dependabot is the usual path, not the only one.

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

CodeQL has no workflow file in this repository. It runs under **default setup**, whose
triggers are managed by GitHub and configured in Settings → Code security — typically
pull requests and pushes to the default branch plus a weekly scan. Because the schedule
is not expressed in this repository, CodeQL's continuity evidence is the scan history in
Security → Code scanning → Tools rather than anything reviewable here.

The `paths: ['app/**']` filter does not create a coverage gap: Brakeman analyzes only
the Rails application, so a change outside `app/**` is outside its analysis surface.

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

### What these windows do and do not cover

**Findings that block a merge are out of scope for the windows below.** Any unsuppressed
Brakeman warning fails the build (section 3), so a finding introduced by a pull request
is resolved — fixed or dispositioned — before the code can merge. That path is enforced
mechanically and needs no service-level commitment.

The windows below therefore govern only findings that appear *without* a code change:
those surfaced by the weekly scheduled scan, by a scanner upgrade that adds new checks,
or by CodeQL, which is not a merge gate. That is a smaller and inherently less urgent
population, which is what makes unhurried windows defensible rather than lax.

### Triage — driven by Brakeman confidence

Triage means: assign a severity, then either fix the finding or suppress it with a
justification under section 4. Business days exclude weekends and US federal holidays.

| Confidence | Triage within |
|---|---|
| High | 5 business days |
| Medium | 10 business days |
| Weak | At the next scheduled review, and no less often than monthly |

### Remediation — driven by assessed severity

Severity is assigned at triage from the CWE, the reachability of the code path, and
whether the affected route is reachable in production. **The remediation clock starts at
triage, when severity is assigned.** A finding dispositioned as a
false positive exits the process at triage and carries no remediation deadline.

| Assessed severity | Remediate within |
|---|---|
| High | 30 days |
| Moderate | 90 days |
| Low | 180 days |

**Evidence.** Each window is measured between three dates. The **triage date** is the
day a severity is assigned and a disposition decided. It is the point at which the
triage window closes and the remediation window opens.

| Date | Definition | Source |
|---|---|---|
| Detection | The scan run that first reported the finding | `scan_info.end_time` in the archived report, or the code scanning alert's creation date |
| Triage | Severity assigned and disposition decided | Recorded by hand on the ticket |
| Resolution | Fix merged, or suppression entry merged | Pull request merge date |

Detection and resolution are derivable from artifacts that already exist. Triage is the
only date requiring deliberate recording. For a finding that is **suppressed**, triage
and resolution are the same event — the merge of the suppression PR — so no separate
record is needed. The triage date does independent work only for findings intended to be
**fixed**, where severity is assigned and remediation then runs to its deadline.

## 6. Evidence capture and retention

Each scan emits a machine-readable report that is archived immutably, so the security
posture of any given commit can be reconstructed after the fact.

**What is captured.** `brakeman -f json` produces a report whose `scan_info` already
records `brakeman_version`, `ruby_version`, `rails_version`, start and end timestamps,
duration, the full list of all the checks performed, and object counts (controllers,
models, templates). `.github/scripts/enrich_brakeman_report.rb` then adds contextual details:

| Field | Purpose |
|---|---|
| `commit_sha` | Exact code state scanned |
| `ref` | Branch scanned |
| `repository` | Source repository |
| `workflow_run_url` | Link back to the run's logs |
| `run_attempt` | Distinguishes re-runs of the same commit |

The report is generated **before** the gate and published regardless of outcome.

**Where it goes.** `s3://dpw-iv-cbv-payroll-security-scan-reports/brakeman/YYYY/MM/DD/<commit-sha>/run-<run-id>-attempt-<n>.json`,
keyed by date and commit SHA.

**Why not GitHub Actions artifacts.** Artifact retention is capped at 90 days on public
repositories, below any plausible AU-11 window.

**Bucket controls** (`infra/app/security-scan-reports/`):

| Control | Setting |
|---|---|
| Versioning | Enabled |
| Object Lock | Enabled, **GOVERNANCE** mode, 3-year (1095-day) default retention — deletion and overwrite are blocked for every principal *except* those holding `s3:BypassGovernanceRetention` |
| Encryption | AES256 at rest |
| Transport | TLS required by bucket policy |
| Public access | Blocked |

**Lifecycle.** Retention is enforced by lifecycle rules:

| Phase | Age | Storage class |
|---|---|---|
| Hot | 0–90 days | S3 Standard — matches the AU-11 "online" anchor |
| Archive | 90 days – expiry | Glacier Instant Retrieval |
| Expiration | `expiration_days` (default 1095 / 3 years) | Deleted |

> **Status — not yet operational; only the bucket is missing.** The publishing path
> has been verified end to end on a real CI run (2026-08-12): the report is generated
> and enriched, Terraform resolves the prod account and role, OIDC federation succeeds
> (`Assuming role with OIDC` → `Authenticated as assumedRoleId …:GitHubActions`), and
> the 7.6 KiB report transfers in full before S3 rejects it with `NoSuchBucket`.
> Nothing in the workflow remains unproven.
>
> The bucket is created by a
> manual `make infra-update-app-security-scan-reports APP_NAME=app`, and
> `object_lock_retention_days` has no default and must be set deliberately, because
> Object Lock retention can be increased later but never decreased. Until the bucket
> is applied, the publish steps carry `continue-on-error: true` so they do not take
> `main` red; **both must be removed once the bucket exists**, otherwise a silently
> broken archive reads as a passing build.

### CodeQL evidence is retained by GitHub

The archive described above covers Brakeman only. Default setup produces no SARIF we
control, so CodeQL results live solely in GitHub's code scanning service — under
GitHub's retention rather than ours, mutable (alerts can be dismissed, analyses deleted),
and lost if the repository is. **This has been accepted as sufficient for CodeQL**: open
alerts are retained for the life of the account and closed alerts stay fully accessible
for two years before moving to full-fidelity archival storage. Exporting to S3 for parity
with Brakeman was considered and deliberately not built.

## Open items

| # | Item | Blocking |
|---|---|---|
| 1 | **Confirm the AU-11 retention window against the control matrix.** 3 years (1095 days) has been set for both `object_lock_retention_days` and `expiration_days` as a considered choice, not a matrix citation — GovRAMP inherits NIST 800-53 Rev 5, where AU-11 is an organization-defined parameter. No longer blocking the apply: GOVERNANCE mode means the value can be corrected in either direction. | An evidenced retention claim |
| 2 | Confirm `Brakeman Scan` is a required status check on `main` (section 3) | Citing the gate as an implemented control |
| 3 | **Approve this document as policy.** It is new in its entirety, so no section is ratified yet — the remediation windows in section 5 are simply the most visible example. Approval should cover the whole document rather than being attributed section by section. | Citing any section as established policy |
| 4 | Apply the bucket, then remove both `continue-on-error: true` lines (section 6) | Evidence capture becoming operational |
| 5 | Record CodeQL default setup's **query suite** (Default vs Extended) in section 1 — it is set in repository settings and cannot be read from the repo. Extended finds more at some cost in precision. | An accurate ruleset column |
| 5b | Create a task to enable code scanning merge protection for CodeQL — Settings → Rules → Rulesets → branch ruleset on `main` → Code scanning → tool `CodeQL`, with alert and security-alert thresholds. Requires admin. Note default setup's own check is not a gate on its own. | Gating parity with Brakeman |
| 5c | Investigate CodeQL's Go coverage (1/2 files) and Ruby (469/473). Small gaps, but an assessor will ask what the unscanned files are. | Complete coverage claim |
| 6 | Enable "Require review from Code Owners" on `main` (section 4). `.github/CODEOWNERS` now exists; the branch protection setting is the remaining half and is covered by the admin ticket. | Mechanical approval control |
