# Halfcycle guard — GitHub Actions

**Halfcycle-internal.** Setting up a project's CI is part of the project, not something
Halfcycle does for a client — this action, and the exchange it calls, exist for
**Halfcycle's own repositories**. Binding a repository is done by a Halfcycle engineer
directly against the control plane, not by a step you run yourself.

Check every change against a project's guards, in CI, with no secret stored
anywhere.

```yaml
name: Halfcycle guard
on:
  push:
  pull_request:

jobs:
  guard:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: Halfcycle-AI/guard-ci@v1
```

**No workflow yet?** Save that as `.github/workflows/halfcycle-guard.yml`. It is a
complete file: commit it, and the check runs on the next push and on every pull
request. **Already have one?** Copy the `guard` job under its `jobs:` key. The job
carries its own `permissions` block, so nothing else in your file changes — no
other job gains or loses a permission.

That permissions block is the whole of what your project configures. There is no
token to put in your repository's secrets, no project id to look up, and no
address to set.

**Both lines, not just the second.** Declaring any permission replaces the
defaults rather than adding to them, so a block naming only `id-token` takes read
access away from `actions/checkout` and a private repository stops checking out
before the guard is reached. It sits on the job, not at the top of the file, for
the same reason: a workflow-level block would replace the defaults for every
other job in that file too.

## What has to happen first, once

```
npx halfcycle
```

writes the guard into the repository — commit what it writes, including
`.halfcycle/bin/`. Separately, a Halfcycle engineer binds the repository against
the control plane's trust-binding route, signed in with their own account
credential — there is no CLI step for this any more. Binding is the only thing
that makes a CI run mean anything: without it, Halfcycle has a signed statement of
which repository the job is in and no idea whose project that is. The check says
exactly that if it is skipped.

## What happens on each run

The job asks GitHub for a short-lived, signed token naming the repository it is
running in — that is what the permission line allows — and trades it for a
credential that lives for minutes. Nothing is stored at either end, so there is
nothing to rotate and nothing to leak. A change that trips a blocking guard fails
the job; a clean one passes it; and either way the check prints what it evaluated
and what it compared against.

## `fetch-depth: 0`

Recommended, not required. A checkout is shallow by default, and the check needs
the commit before the one it is evaluating. If your checkout is shallow the step
deepens it itself and says so — setting it on the checkout is simply faster than
having this step do it.

## If you already have the older setup

A job that still passes `GUARD_SERVICE_TOKEN` and `GUARD_ENGAGEMENT_ID` keeps
working unchanged: a stored credential is used whenever it is complete. To move
off them, delete both from the job and from your repository's secrets, and add the
permission line. Nothing else changes.

## Inputs

| Input | Default | What it is for |
| --- | --- | --- |
| `working-directory` | `.` | The directory holding your project, if it is not the root of the checkout. |
| `diff-base` | *(unset)* | The commit this change started from, if your workflow already knows it — on a push event, `${{ github.event.before }}`. Leave it unset and the check works it out. |

## When it will not run

Each of these fails the job with the fix in the message, because a check that
cannot run must never be mistaken for a check that found nothing.

- **No repository checked out** — add `actions/checkout` before the step.
- **No guard in the checkout** — run `npx halfcycle` in the project and commit
  what it writes. The guard runs out of your own repository.
- **No Node on the runner** — add `actions/setup-node` before the step. This step
  will not install one for you: changing the Node version your workflow builds
  with is not something a check should do behind your back.
- **No permission** — add the permissions block above to the job, both lines of it.
- **This repository is claimed by nobody** — a Halfcycle engineer has not bound it
  yet. The message names the repository it verified, so it is clear which one to
  bind.
