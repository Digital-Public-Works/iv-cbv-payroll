# How to Contribute

This project is being developed by Digital Public Works in partnership with various agency partners. We use internal
tools to track our work (bugs and feature enhancements), and as such this repo is not architected to receive
public contributions.

## Testing Conventions

Tests live in `app/spec`, mirroring the structure of `app/app`. See the [README](./README.md) for running the full
test suite.

### Automated accessibility checks

The end-to-end (E2E) specs in `app/spec/e2e` are also where the automated accessibility checks live. Every call to
`verify_page` (`app/spec/support/e2e/test_helpers.rb`) runs [axe-core](https://github.com/dequelabs/axe-core) against the
current page using its default ruleset (WCAG 2.1 A/AA), so any page you visit through `verify_page` is checked. When
you add a new page or a new state of a page to an E2E spec, check it with `verify_page`.

These specs run automatically on every pull request that changes `app/`. To run them locally, from the `app`
directory:

```sh
E2E_RUN_TESTS=1 bin/rspec spec/e2e
```

Add `E2E_SHOW_BROWSER=1` to watch the browser instead of running headless. See
[docs/e2e/e2e-checks.md](./docs/e2e/e2e-checks.md) for record/replay mode and writing new E2E specs.

**Automated checks catch only part of what matters.** Contextual issues like correct labels, keyboard behavior, focus management, and screen
reader announcements among others still need a person to review them.

### Skipping an accessibility rule

Skipping an axe rule should be a deliberate, documented decision, not a way to get a build green. A skip is acceptable
only when:

- the violation is a known issue with a ticket tracking the fix, or
- the violation is a confirmed false positive (for example, axe misreading markup we don't control).

#### Rules for every skip:

- Skip per page, on the specific `verify_page` call, using `skip_axe_rules:`. Never disable a rule globally.
- Skip only the specific rule ID that fails, not a broader set.
- Put an inline comment directly above the call that names the rule, explains why it fails, and links the tracking
  ticket (or says "false positive" and why).
- Remove the skip when the underlying issue is fixed.

##### Example:
```ruby
# axe-skip color-contrast: the third-party banner renders gray-on-white text we
# can't restyle yet. Tracked in PF-1234.
verify_page(page, title: I18n.t("cbv.example.show.header"), skip_axe_rules: %w[color-contrast])
```

Reviewers should ask for changes on any skip that doesn't follow this pattern.

<details>
<summary>Sections we will fill out once we open to external contributions</summary>
## Getting Started

### Team Specific Guidelines

<!-- TODO: This section helps contributors understand any team structure in the project (formal or informal.) Encouraged to point towards the MAINTAINERS.md file for further details.-->

### Building dependencies

<!--- TODO: This step is often skipped, so don't forget to include the steps needed to install on your platform. If you project can be multi-platform, this is an excellent place for first time contributors to send patches!-->

### Building the Project

<!--- TODO: Be sure to include build scripts and instructions, not just the source code itself! -->

### Workflow and Branching

<!--- TODO: Workflow Example
We follow the [GitHub Flow Workflow](https://guides.github.com/introduction/flow/)

1.  Fork the project
2.  Check out the `main` branch
3.  Create a feature branch
4.  Write code and tests for your change
5.  From your branch, make a pull request against `{{ cookiecutter.project_org }}/{{ cookiecutter.project_repo_name }}/main`
6.  Work with repo maintainers to get your change reviewed
7.  Wait for your change to be pulled into `{{ cookiecutter.project_org }}/{{ cookiecutter.project_repo_name }}/main`
8.  Delete your feature branch
-->

### Coding Style and Linters

<!--- TODO: HIGHLY ENCOURAGED. Specific tools will vary between different languages/frameworks (e.g. Black for python, esliint for JavaScript, etc...)

1. Mention any style guides you adhere to (e.g. pep8, etc...)
2. Mention any linters your project uses (e.g. flake8, jslint, etc...)
3. Mention any naming conventions your project uses (e.g. Semantic Versioning, CamelCasing, etc...)
4. Mention any other content guidelines the project adheres to (e.g. plainlanguage.gov, etc...)

-->

### Writing Issues

<!--- TODO: Example Issue Guides

When creating an issue please try to adhere to the following format:

    module-name: One line summary of the issue (less than 72 characters)

    ### Expected behavior

    As concisely as possible, describe the expected behavior.

    ### Actual behavior

    As concisely as possible, describe the observed behavior.

    ### Steps to reproduce the behavior

    List all relevant steps to reproduce the observed behavior.

    see our .github/ISSUE_TEMPLATE.md for more examples.
-->

### Writing Pull Requests

<!-- TODO: Make a brief statement about where to file pull/merge requests, and conventions for doing so. Link to PULL_REQUEST_TEMPLATE.md file.

Comments should be formatted to a width no greater than 80 columns.

Files should be exempt of trailing spaces.

We adhere to a specific format for commit messages. Please write your commit
messages along these guidelines. Please keep the line width no greater than 80
columns (You can use `fmt -n -p -w 80` to accomplish this).

    module-name: One line description of your change (less than 72 characters)

    Problem

    Explain the context and why you're making that change.  What is the problem
    you're trying to solve? In some cases there is not a problem and this can be
    thought of being the motivation for your change.

    Solution

    Describe the modifications you've done.

    Result

    What will change as a result of your pull request? Note that sometimes this
    section is unnecessary because it is self-explanatory based on the solution.

Some important notes regarding the summary line:

* Describe what was done; not the result
* Use the active voice
* Use the present tense
* Capitalize properly
* Do not end in a period — this is a title/subject
* Prefix the subject with its scope

    see our .github/PULL_REQUEST_TEMPLATE.md for more examples.
-->

## Reviewing Pull Requests

Code Review Example

When you submit a PR to on GitHub it will be reviewed by the project maintainers,
and once changes are approved will be squashed and merged into the main repository.

The changes in the pull request will be collapsed into a single commit, but the
authorship metadata will be preserved.

-->
