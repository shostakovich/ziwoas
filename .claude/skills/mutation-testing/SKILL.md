---
name: mutation-testing
description: Mutation testing with the mutant gem in ZiWoAS, scoped to the subjects touched in the current session. Use at the end of a session, before a PR, after a refactor, when test coverage should actually be validated, or when asked about "mutant", "mutation testing" or "100 % test coverage".
---

# Mutation testing with mutant

Coverage measures **execution**, not **verification**. In this repo `lib/power_series.rb` had
100 % line and branch coverage — and four mutations still survived (among them
`role == :producer` → `true` and `ts >= ?` → `ts > ?`). Mutation testing closes that gap.

**Scope: only what this session changed or added.** A run over the whole codebase takes long
and surfaces thousands of survivors in old code — that's noise, not a finding.

## Already in place

- `mutant-minitest` in the Gemfile test group.
- [`config/mutant.yml`](../../../config/mutant.yml): `usage: opensource` (the repo is public),
  minitest integration, `requires: [mutant_helper]`, includes `test` and `lib`.
- [`test/mutant_helper.rb`](../../../test/mutant_helper.rb): entry point that disables
  minitest's `at_exit` runner and eager-loads the app. **Leave it alone** — without that trick
  every killfork reruns the entire suite.
- Sessions are stored in `.mutant/` (gitignored).

## Workflow

### 1. Find the changed subjects

```bash
git diff --name-only $(git merge-base HEAD main)...HEAD -- app lib
```

Turn paths into mutant expressions: `app/models/plugs/roster.rb` → `Plugs::Roster*`,
`lib/power_series.rb` → `PowerSeries*`. The star includes all methods of the subject.

### 2. Make sure the tests declare `cover`

**This is the trap.** Mutant does not find a subject's tests on its own. Every test class
covering the subject needs a declaration:

```ruby
class PowerSeriesTest < ActiveSupport::TestCase
  cover "PowerSeries*"
  ...
end
```

Without it the run reports `Selected-Tests: 0` and **every** mutation survives. That is not a
coverage finding, it's a missing declaration — add `cover`, then rerun. Examples:
`test/lib/power_series_test.rb`, `test/models/plugs/roster_test.rb`.

### 3. Run it

```bash
PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8 bundle exec mutant run -- 'PowerSeries*' 'Plugs::Roster*'
```

- `PATH` prefix: non-interactive shells don't load rbenv and end up on Ruby 2.6.
- `LANG=en_US.UTF-8`: without a UTF-8 locale mutant aborts reading its session file with
  `Encoding::InvalidByteSequenceError` as soon as mutated source contains umlauts.
- Append as many expressions as needed.
- `--fail-fast` stops at the first survivor — useful while iterating.

`--since` is a filter, not a selector; without subject expressions it yields zero subjects:

```bash
PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8 bundle exec mutant run --since main -- 'Plugs*' 'Switching*'
```

### 4. Read the result

```
Selected-Tests:  27      <- 0 means cover is missing (step 2), not "no tests"
Mutations:       444
Kills:           444
Alive:           0       <- the goal
Coverage:        100.00% <- mutation coverage, not line coverage
```

`Alive: 0` / `Coverage: 100.00%` → done. Otherwise continue.

### 5. Inspect the survivors

All subjects of the last session:

```bash
PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8 bundle exec mutant session subject
```

The concrete diffs for one subject:

```bash
PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8 bundle exec mutant session subject 'Plugs::Measurement::Collection#total_w'
```

Each survivor comes as a diff — exactly the behaviour no test would have noticed.

### 6. Write the missing tests

For every survivor, write a test that **kills** it:

1. Write a test that reacts to the mutated behaviour.
2. Prove it bites: apply the mutation by hand → test turns red → revert the mutation → test
   turns green. Without that proof it's unclear whether the test really catches the mutation.
3. Rerun `mutant run` for that subject until `Alive: 0`.

**Don't bend production logic to get rid of mutations.** The finding is a test gap, not a code
weakness.

### 7. Equivalent mutations

Some mutations don't change behaviour (typically pure presentation, logging, defensive branches
that are functionally unreachable). Those can't be killed. Instead of forcing them: name them
in the PR or the session summary — subject, mutation, reasoning — and make the rest green.
Silently ignoring an unkillable mutation is the worse option.

## Delegating to a subagent

The run and the follow-up tests suit a subagent well (Sonnet is enough). Give it:

- The concrete subject expressions — not "the changed files", which it can't see.
- The full command prefix `PATH="$HOME/.rbenv/shims:$PATH" LANG=en_US.UTF-8`.
- The `cover` rule from step 2, including "`Selected-Tests: 0` is not a test gap".
- The red/green proof obligation from step 6.
- The constraint to **touch test files only** and to revert every mutation it applied for
  checking. For new, untracked files `git checkout` saves nothing — end with `git diff` over
  `app/` and `lib/` and confirm nothing was left behind.
- As the report: a table of survivors, which tests were written for them, and which ones were
  classified as equivalent.

## Finally

Run `bin/ci` — the new tests have to be green in the regular suite and must not drop below the
SimpleCov floor.
