load test_helper

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

# No file-level teardown(): only two of the three tests below ever call
# setup_sandbox, and teardown_sandbox's `[[ ... ]] && rm -rf ...` guard trips
# `set -e` when SANDBOX was never set (an unset "left side" makes the `&&`
# expression itself false). Sandboxed tests clean up for themselves instead.

# check_pre_commit must hard-fail (not soft-skip-with-a-warning) when
# pre-commit isn't installed — issue #59: a soft-skip here would silently
# reintroduce the exact false-green gap this gate exists to close.
@test "check_pre_commit hard-fails when pre-commit is not installed" {
  local fakebin
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  # A PATH with no pre-commit on it at all.
  run env PATH="$fakebin:/usr/bin:/bin" bash -c "
    source '$REPO/bin/dot-test'
    check_pre_commit
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"pre-commit"* ]]
  [[ "$output" != *"skipping"* ]]
}

# dot-test derives DOTFILES from its own location, ignoring any inherited env
# var (issue #30) — so to point check_pre_commit at a sandboxed tree, the
# sandbox must carry its own copy of bin/dot-test, exactly like
# tests/dot_test_root.bats does for the same reason.
_seed_shebang_fixture() {
  local mode="$1" # "executable" or "not-executable"
  cp "$REPO/bin/dot-test" "$DOTFILES/bin/dot-test"

  cat >"$DOTFILES/.pre-commit-config.yaml" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-shebang-scripts-are-executable
EOF

  printf '#!/usr/bin/env bash\necho hi\n' >"$DOTFILES/bin/fixture.sh"
  if [[ "$mode" == "executable" ]]; then
    chmod +x "$DOTFILES/bin/fixture.sh"
  else
    chmod -x "$DOTFILES/bin/fixture.sh"
  fi

  git -C "$DOTFILES" init -q
  # Force filemode tracking on: git auto-detects core.fileMode per-repo by
  # probing the filesystem at `git init` time, and some CI tmpdirs (e.g. the
  # mktemp -d sandbox root on GitHub's Ubuntu runners) probe false even
  # though chmod +x/-x above genuinely changed the bit on disk. Without this,
  # `git add` silently records every file as 100644 regardless of its real
  # mode, so check-shebang-scripts-are-executable (which reads the mode git
  # recorded, not the filesystem) sees "not executable" even after chmod +x —
  # exactly the false failure seen on CI's Linux job but not macOS.
  git -C "$DOTFILES" config core.fileMode true
  git -C "$DOTFILES" config user.email "test@example.com"
  git -C "$DOTFILES" config user.name "Test"
  git -C "$DOTFILES" add -A
  git -C "$DOTFILES" commit -q -m "sandbox fixture"
}

# Sandboxed real pre-commit run: a script has a shebang but is missing the
# executable bit — exactly the PR #56/#64 incident. dot-test's pre-commit
# check must catch it, since dot-test is now the single CI-equivalent gate.
@test "check_pre_commit fails when a shebang script is missing the executable bit" {
  command -v pre-commit >/dev/null || skip "pre-commit not installed"
  command -v git >/dev/null || skip "git not installed"

  setup_sandbox
  _seed_shebang_fixture "not-executable"

  run bash -c "source '$DOTFILES/bin/dot-test'; check_pre_commit"
  teardown_sandbox
  [ "$status" -ne 0 ]
}

# Confirm the good path: once the script is made executable, the same check
# passes — proves the failure above is specific to the missing bit, not the
# sandbox itself.
@test "check_pre_commit passes once the shebang script is made executable" {
  command -v pre-commit >/dev/null || skip "pre-commit not installed"
  command -v git >/dev/null || skip "git not installed"

  setup_sandbox
  _seed_shebang_fixture "executable"

  run bash -c "source '$DOTFILES/bin/dot-test'; check_pre_commit"
  teardown_sandbox
  [ "$status" -eq 0 ]
}
