## Summary
PF-868: brings accessibility into the team's existing documentation. The finalized "Best Practices by Role" guidance (Design & UX, Engineering, QA / Manual Testing) now lives in the repo and is linked from the contributor docs. The PR template and code review guide now ask authors and reviewers to confirm accessibility was checked. A manual audit checklist covers what automated axe checks can't.

## Type of Change
Check all that apply.
- [ ] Bug
- [ ] Feature
- [ ] Refactor
- [x] Documentation update

## Changes
- Add `docs/accessibility/best-practices-by-role.md`, the Design & UX, Engineering, and QA / Manual Testing checklists plus an Additional resources section, with an updated Accessibility Pane screenshot
- Link to the best practices from a new Accessibility section in `CONTRIBUTING.md` and from the README's automated accessibility checks section
- Add an "Audited for A11y" checkbox to the PR template, linking to the Engineering best practices, with sub-items for the QA / Manual Testing checklist and a recorded keyboard and screen reader demo
- Add an Accessibility section for reviewers to `docs/code-reviews.md`
- Add `docs/accessibility/manual-audit-checklist.md`, a 6-month manual audit of the major user paths (owner: Kali, through March 2027), including a review of accepted `skip_axe_rules` risks

## Checklist
- [ ] Tests added/updated (if needed)
- [x] Docs updated (if needed)
- [ ] Audited for A11y (if needed, see [Engineering best practices](https://github.com/Digital-Public-Works/iv-cbv-payroll/blob/main/docs/accessibility/best-practices-by-role.md#engineering))
  - [ ] [QA / Manual Testing checklist](https://github.com/Digital-Public-Works/iv-cbv-payroll/blob/main/docs/accessibility/best-practices-by-role.md#qa--manual-testing) completed
  - [ ] Demo recorded using keyboard and screen reader

## Notes for Reviewers
- The best-practices content is copied from the team's finalized "Accessibility Processes and Best Practices" doc and changed only for markdown formatting. Beyond that: the Reflow link was fixed, an Open UI resource was added, and the screenshot was replaced with a browser-agnostic one. Please review wording changes against the source doc rather than editing here.
- The PR template uses absolute `blob/main` links, because relative links don't resolve in PR descriptions. They'll 404 until this merges.
- The audit checklist has placeholders for "Performed by" and the dates. Who performs the audit (internal or external vendor) is still an open team question.
- Two "§4" links in the Engineering section and Additional resources point to the Feature Lifecycle section of the source doc, which isn't in the repo. Open question: remove them or bring that section in.
- Out-of-repo pieces (the Asana ticket template, the Google Doc pointer, and audit scheduling) are handled outside this PR.
