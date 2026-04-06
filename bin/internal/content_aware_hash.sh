#!/usr/bin/env bash
# Copyright 2014 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# ---------------------------------- NOTE ---------------------------------- #
#
# Please keep the logic in this file consistent with the logic in the
# `content_aware_hash.ps1` script in the same directory to ensure that Flutter
# continues to work across all platforms!
#
# -------------------------------------------------------------------------- #

set -e

FLUTTER_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"

unset GIT_DIR
unset GIT_INDEX_FILE
unset GIT_WORK_TREE

# Cannot use '*' for files in this command
# DEPS: tracks third party dependencies related to building the engine
# engine: all the code in the engine folder
# bin/internal/release-candidate-branch.version: release marker
TRACKEDFILES=(DEPS engine bin/internal/release-candidate-branch.version)
BASEREF="HEAD"
CURRENT_BRANCH="$(git -C "$FLUTTER_ROOT" rev-parse --abbrev-ref HEAD)"

# By default, the content hash is based on HEAD.
# For local development branches, we want to base the hash on the merge-base
# with the remote tracking branch, so that we don't rebuild the world every
# time we make a change to the engine.
#
# The following conditions are exceptions where we want to use HEAD.
# 1. The current branch is a release branch (main, master, stable, beta).
# 2. The current branch is a GitHub temporary merge branch.
# 3. The current branch is a release candidate branch.
# 4. The current checkout is a shallow clone.
# 5. There is no current branch. E.g. running on CI/CD.
if [[ "$CURRENT_BRANCH" != "main" && \
      "$CURRENT_BRANCH" != "master" && \
      "$CURRENT_BRANCH" != "stable" && \
      "$CURRENT_BRANCH" != "beta" && \
      "$CURRENT_BRANCH" != "gh-readonly-queue/master/pr-"* && \
      "$CURRENT_BRANCH" != "flutter-"*"-candidate."* && \
      ! ( "$CURRENT_BRANCH" == "HEAD" && -n "$LUCI_CONTEXT" ) && \
      ! -f "$FLUTTER_ROOT/.git/shallow" ]]; then

  # This is a development branch. Find the merge-base.
  # We will fallback to origin if upstream is not detected.
  REMOTE="origin"
  if git -C "$FLUTTER_ROOT" remote get-url upstream >/dev/null 2>&1; then
    REMOTE="upstream"
  fi

  # Try to find the merge-base with master, then main.
  MERGEBASE=$(git -C "$FLUTTER_ROOT" merge-base HEAD "$REMOTE/master" 2>/dev/null || true)
  if [[ -z "$MERGEBASE" ]]; then
    MERGEBASE=$(git -C "$FLUTTER_ROOT" merge-base HEAD "$REMOTE/main" 2>/dev/null || true)
  fi

  if [[ -n "$MERGEBASE" ]]; then
    BASEREF="$MERGEBASE"
  fi
fi

# Capture git ls-tree output separately so we can detect failures.
# A pipeline would mask a non-zero exit from ls-tree (set -e only
# checks the last command in a pipeline when pipefail is not set).
# See https://github.com/flutter/flutter/issues/184523.
TREE_OUTPUT="$(git -C "$FLUTTER_ROOT" ls-tree "$BASEREF" -- "${TRACKEDFILES[@]}")" || {
  >&2 echo ""
  >&2 echo "Error: Unable to compute the content hash of the Flutter SDK."
  >&2 echo "'git ls-tree' failed for ref '$BASEREF'."
  >&2 echo ""
  >&2 echo "This is most commonly caused by an incompatible version of git."
  >&2 echo "  git binary : $(command -v git)"
  >&2 echo "  git version: $(git --version 2>/dev/null || echo 'unknown')"
  >&2 echo ""
  >&2 echo "If this Flutter SDK was cloned or last used with a different version of"
  >&2 echo "git, ensure that version is available in your PATH, or re-clone the SDK"
  >&2 echo "with the current version of git."
  exit 1
}

if [ -n "$TREE_OUTPUT" ]; then
  printf '%s\n' "$TREE_OUTPUT" | git hash-object --stdin
else
  >&2 echo "Error: 'git ls-tree' produced empty output for ref '$BASEREF'."
  exit 1
fi
