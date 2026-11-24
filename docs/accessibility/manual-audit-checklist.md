# Manual Accessibility Audit Checklist

Automated axe checks run on every pull request (see
[Automated accessibility checks](../../README.md#automated-accessibility-checks)), but they can't confirm
contextual issues like accurate labels, keyboard behavior, focus management, or screen reader announcements. This
audit covers those gaps across the major user paths.

- **Cadence:** every 6 months
- **Owner:** Kali, through March 2027. A platform team owner will be named after that.
- **Performed by:** [TODO: internal owner or external vendor]
- **Last completed:** [date]
- **Next due:** [date]

## How to run it

For each path below, run the
[QA / Manual Testing checklist](./best-practices-by-role.md#qa--manual-testing) (automated checker, color contrast,
accessibility tree, keyboard-only, screen reader, element list) in English and Spanish, and also check:

- [ ] Zoom to 200%: no lost content or functionality
- [ ] Reflow at 400% (320px): no horizontal scrolling
- [ ] Focus moves to a sensible place after each page load, modal open/close, and error

In non-production environments, the `/cbv/preview` routes render each page without walking the full flow.

## Major user paths

### Applicant (CBV flow)

- [ ] Entry: invitation link and landing page (`/cbv/entry`, `/cbv/landing_page`)
- [ ] Expired invitation (`/cbv/expired_invitation`)
- [ ] Applicant information (`/cbv/applicant_information`)
- [ ] Employer search, including the Argyle connection modal: focus moves in and returns on close
      (`/cbv/employer_search`)
- [ ] Synchronization, including the failure and validation-failure states (`/cbv/synchronizations`,
      `/cbv/synchronization_failures`, `/cbv/validation_failures`)
- [ ] Payment details (`/cbv/payment_details`)
- [ ] Add job / other job (`/cbv/add_job`, `/cbv/other_job`)
- [ ] Summary and missing results (`/cbv/summary`, `/cbv/missing_results`)
- [ ] Review and submit, including the PDF income report (`/cbv/submit`, `/cbv/submit.pdf`)
- [ ] Success (`/cbv/success`)
- [ ] Help modal: focus trapping, Escape/close, and focus return
- [ ] Session timeout warning modal and timeout page (`/cbv/session/timeout`)
- [ ] Form validation errors on each form page (announced, tied to the field via `aria-describedby`)

### Caseworker portal

- [ ] Sign-in and entry pages (`/:client_agency_id`)

## Review accepted risks

- [ ] List every axe rule skip: `grep -rn "skip_axe_rules:" app/spec/e2e`
- [ ] Confirm each skip still follows the
      [Skipping an accessibility rule](../../CONTRIBUTING.md#skipping-an-accessibility-rule) policy, and remove any
      whose tracking ticket is closed.
- [ ] Confirm every page added since the last audit is visited through `verify_page` in an E2E spec.

## After the audit

- [ ] Log each finding as a ticket and tag it "a11y"
- [ ] Update **Last completed** and **Next due** above
