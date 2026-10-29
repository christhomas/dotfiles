# User-level engineering rules

## Test execution and CI

- Finish the complete implementation for an issue before running any test suite.
- Never run test suites after incremental edits or small code changes.
- Use one issue per branch and pull request; push the completed issue branch so GitHub CI performs validation.
- At issue closure or another genuinely important integration boundary, local verification is limited to the smallest targeted reproduction or smoke check needed.
- Do not run the repository-wide suite locally unless reproducing a specific CI failure.
- GitHub CI must run the complete repository test suite. If it does not, improve CI coverage instead of compensating with repeated local full-suite runs.

## Agent attempt limits

- A delegated issue gets at most three failed attempts at the same blocker. If it has not produced a concrete artifact, diagnosis, or verified result by then, stop or park it and move to the next issue.
- Never leave a subagent running unattended through repeated failed attempts. Inspect progress and terminate stalled work before it consumes material quota.
- Delegation must state a bounded deliverable and stopping condition. No-result exploration is not permission to keep spending tokens.
## Issue closure timing

- For christhomas/ai.world, keep the timing ledger at ~/.omp/agent/issue-cycle-times.json. Record a UTC run start before issue work and each verified merge immediately after it happens.
- The current-method average is total wall minutes since the monitored run began divided by issues merged in that run. Time spent on failed or parked attempts remains in the numerator; never omit unsuccessful work or redefine the metric mid-run.
- Compare against the persisted legacy arithmetic mean, currently 65.33 minutes per closed issue. Before the first closure, reaching that elapsed time is a failure. After each closure, an average greater than or equal to the baseline is a failure.
- On timing failure, immediately stop issue work, cancel running subagents and waits, record the measured result in the ledger, and report the regression. Resume only after the user chooses a different method.
- Update the ledger after every closure and inspect elapsed time at least every ten minutes while an integration agent is active.
## Pull request order

- For christhomas/ai.world, process open pull requests in strict ascending numeric order: update, audit, and merge the smallest PR number first.
- A newer PR may be processed only after every lower-numbered open PR has either merged or been explicitly parked with a concrete blocker after the attempt limit. Dependencies and CI readiness do not silently override this order.
## CI waiting

- Never spend model or subagent requests polling a pending pipeline. Park or stop the agent at the first pending result.
- Watch CI with a non-model process at 60-second intervals, such as gh pr checks --watch --interval 60. Resume model work only when the pipeline reaches a terminal state or produces an actionable failure.
## Parallel pull-request preparation

- While the current lowest-numbered PR waits on CI or review, actively prepare the next open PR: inspect, resolve findings, rebase, edit, run targeted checks, and push as appropriate.
- Serialize only merges: never merge a higher-numbered PR while a lower-numbered PR remains unmerged and not explicitly parked. Do not leave the agent idle during a non-model CI wait.
- Do not wait idly even when the next branch appears current: verify its base, inspect and resolve its findings, run targeted checks, and push any required update before returning to the waiting PR when its pipeline becomes terminal.
## Review handoff before merge

- Before attempting to merge any PR, inspect all comments, inline threads, human reviews, and automated or agent-review findings.
- For actionable review findings, create one follow-up GitHub issue grouping the related findings, with the PR URL, review/thread URLs, exact scope, affected files or symbols, and expected behavior.
- Do not modify the current PR for deferred review findings. Proceed with the merge after required CI and normal merge gates pass; a later agent will implement the issue in a separate PR.
- This handoff does not defer broken required CI, type errors, failed tests, or failed builds; those still block merging.
- Keep this workflow generic: discover the live open queue at runtime and derive the current smallest PR and next preparation target. Do not hardcode specific PR numbers in reusable agent instructions.
