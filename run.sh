#!/usr/bin/env bash
#
# The Halfcycle guard check, as a CI job runs it.
#
# Four things have to be true before the check can run, and each one is a
# different thing for a person to do. A job that fails with "it did not work"
# sends whoever reads the log to the wrong place, so each is checked separately
# and each says what to change. Nothing here explains how the guard works; a CI
# log is read by somebody who wants to get back to what they were doing.
#
# THE EXIT CODE IS THE GUARD'S. The last line runs the check and nothing follows
# it, so a blocked change fails the job and a clean one passes it. That is the
# whole contract this file has with the workflow around it.

set -uo pipefail

# The guard binary, committed inside the project by `npx halfcycle`. It is a
# self-contained file: no package manager, no install step, no lockfile. That is
# what lets this action work in a Python or Go project as well as a JavaScript
# one, and why the only tool this job needs is Node.
BIN=".halfcycle/bin/bin.bundle.mjs"

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 1. The project has to be checked out.
# -----------------------------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  fail "Halfcycle: there is no repository here to check.
Add the checkout step before this one:

    - uses: actions/checkout@v4
    - uses: <the Halfcycle guard action>"
fi

# -----------------------------------------------------------------------------
# 2. The guard has to be in the checkout.
#
# It is committed on purpose. The alternative — fetching a version-matched binary
# at the start of every CI run — makes every client's build depend on a download
# to run a check that is supposed to be cheap.
# -----------------------------------------------------------------------------
if [ ! -f "$BIN" ]; then
  fail "Halfcycle: this project has no guard to run.
There is no $BIN in this checkout.

Run \`npx halfcycle\` in the project on your own machine, commit what it writes,
and push. The guard runs out of your own repository, so it has to be committed."
fi

# -----------------------------------------------------------------------------
# 3. Node has to be available.
#
# This step does NOT install one. A job that quietly installed a toolchain could
# change the version the rest of the workflow builds with, which is a surprising
# thing for a check to do and a hard thing to find afterwards.
# -----------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  fail "Halfcycle: this step needs Node 20 or newer, and this runner has none.
Add the setup step before this one:

    - uses: actions/setup-node@v4
      with:
        node-version: 20"
fi

# -----------------------------------------------------------------------------
# 4. The job has to be able to prove which project it belongs to.
#
# It does that by asking GitHub for a short-lived signed token naming this
# repository, which GitHub only offers to a job whose workflow has said it may.
# The permissions block is the whole of what a project configures — there is no
# secret to store and no id to set. It has to name `contents: read` as well, and
# that is not padding: declaring ANY permission replaces the defaults instead of
# adding to them, so a block naming only the identity token silently takes read
# access away from the checkout step, and a private repository stops checking out
# before this action is ever reached. Measured on a real run, 2026-09-15.
#
# A job that still carries the older pair of repository secrets keeps working and
# is not asked for the permission: the guard prefers a stored credential whenever
# it has a complete one, so telling such a job to add a permission it does not use
# would be advice that changes nothing.
# -----------------------------------------------------------------------------
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] &&
  { [ -z "${GUARD_SERVICE_TOKEN:-}" ] || [ -z "${GUARD_ENGAGEMENT_ID:-}" ]; }; then
  fail "Halfcycle: this job cannot prove which project it belongs to.
Add this to the workflow — at the top of the file, or on this job:

    permissions:
      contents: read
      id-token: write

BOTH LINES. Declaring any permission replaces the defaults rather than adding to
them, so a block naming only the identity token takes read access away from the
checkout step and a private repository stops checking out.

That is the whole configuration: it lets this job ask GitHub for a short-lived
signed token naming this repository, and Halfcycle trusts the name GitHub signs
rather than anything the job says about itself. There is no secret to store, no
project id to set and no address to configure."
fi

# -----------------------------------------------------------------------------
# 5. Enough history to know what changed.
#
# A checkout is shallow by default, which means the commit BEFORE this one is not
# present — and without it there is no way to tell what this change consists of.
# Deepening here rather than asking for it back is what keeps the promise that one
# permission line is the whole configuration. A workflow that already sets
# `fetch-depth: 0` skips all of this, and that is the faster arrangement.
#
# Both fetches are allowed to fail. If the history is still too short, the check
# itself says so and names the remedy; a network hiccup while deepening must not
# become a second failure with a worse message.
# -----------------------------------------------------------------------------
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
  say "Halfcycle: fetching this project's history — the check needs the commit before this one."
  git fetch --quiet --unshallow origin 2>/dev/null || git fetch --quiet --deepen=100 origin 2>/dev/null || true
fi

# The branch a change is measured against. A checkout fetches only the ref it
# checked out, so on a branch build the default branch is often absent and the
# check falls back to comparing against the previous commit alone — narrower than
# the change actually is, and silent about it.
if ! git rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 &&
  ! git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
  git fetch --quiet origin '+refs/heads/*:refs/remotes/origin/*' 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 6. The check. Its exit code is this step's, and nothing runs after it.
# -----------------------------------------------------------------------------
node "$BIN" ci
