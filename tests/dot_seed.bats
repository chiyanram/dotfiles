load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# Seed Targets (ADR-0008): a home/<path>.seed source is copied once to
# ~/<path> (suffix stripped), never symlinked, and never overwritten once the
# owning tool has taken it over.

seed_fixture() {
  mkdir -p "$DOTFILES/home/.claude"
  printf '%s\n' "${1:-SHIPPED}" >"$DOTFILES/home/.claude/settings.json.seed"
}

@test "link all seeds a .seed home file as a real copy at the suffix-stripped target" {
  seed_fixture 'SHIPPED'
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/settings.json" ] # exists at the stripped path
  [ ! -L "$HOME/.claude/settings.json" ]        # a copy, not a symlink
  [ ! -e "$HOME/.claude/settings.json.seed" ]   # no stray .seed target
  [ "$(cat "$HOME/.claude/settings.json")" = "SHIPPED" ]
}

@test "seed is copy-once: an existing app-modified target is never clobbered" {
  seed_fixture 'SHIPPED'
  mkdir -p "$HOME/.claude"
  printf 'APP-MODIFIED\n' >"$HOME/.claude/settings.json"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = "APP-MODIFIED" ]
}

@test "seeding is idempotent: a second link all leaves the app's writes intact" {
  seed_fixture 'SHIPPED'
  "$DOT" link all
  printf 'APP-WROTE-THIS\n' >"$HOME/.claude/settings.json"
  run "$DOT" link all
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = "APP-WROTE-THIS" ]
}

@test "--reseed overwrites a seeded target and backs up the old file" {
  seed_fixture 'SHIPPED'
  mkdir -p "$HOME/.claude"
  printf 'OLD\n' >"$HOME/.claude/settings.json"
  run "$DOT" link all --reseed
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = "SHIPPED" ]
  local bak
  bak="$(ls "$HOME/.claude/"settings.json.backup.* 2>/dev/null | head -1)"
  [ -n "$bak" ]
  [ "$(cat "$bak")" = "OLD" ]
}

@test "dot restore removes a freshly-seeded file" {
  seed_fixture 'SHIPPED'
  "$DOT" link all
  [ -f "$HOME/.claude/settings.json" ]
  run "$DOT" restore
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/settings.json" ]
}

@test "unlink all leaves a seeded, app-owned file alone" {
  seed_fixture 'SHIPPED'
  "$DOT" link all
  run "$DOT" unlink all
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/settings.json" ]
  [[ "$output" == *"seeded"* || "$output" == *"app-owned"* ]]
}

@test "link -n previews SEED for an unseeded target" {
  seed_fixture 'SHIPPED'
  run "$DOT" link all -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"SEED"* ]]
}
