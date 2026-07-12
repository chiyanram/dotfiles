setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config" # pin away the real machine's ~/.config
  export DOTFILES="$REPO"
  export TERM=dumb
  unset GH_CONFIG_DIR # don't inherit a dedicated config from the real shell (e.g. direnv)
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$HOME/.config/git/config"
  mkdir -p "$HOME/.config/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1

  # A fake `gh` on PATH that records both its args AND the GH_CONFIG_DIR it saw,
  # so a slot's dedicated config being used (vs. the ambient default) is observable.
  export GH_LOG="$HOME/gh.log"
  mkdir -p "$HOME/bin"
  cat >"$HOME/bin/gh" <<EOF
#!/usr/bin/env bash
printf '[%s] %s\n' "\${GH_CONFIG_DIR:-<default>}" "\$*" >>"$GH_LOG"
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then exit 0; fi
exit 0
EOF
  chmod +x "$HOME/bin/gh"
  export PATH="$HOME/bin:$PATH"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
  : >"$GH_LOG"
}

_mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

# A slot's dedicated gh config is just a real login on disk: ~/.config/gh-<name>/hosts.yml.
_seed_dedicated_gh_config() {
  local name="$1"
  mkdir -p "$HOME/.config/gh-$name"
  printf 'github.com:\n    user: workuser\n' >"$HOME/.config/gh-$name/hosts.yml"
}

@test "gh-config-dir prints nothing outside any repo" {
  run "$REPO/bin/dot-git" gh-config-dir
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "gh-config-dir prints nothing when the repo's slot has no dedicated config yet" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "git@github.com-ee:owner/repo.git"
  cd "$HOME/proj"

  run "$REPO/bin/dot-git" gh-config-dir
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "gh-config-dir prints the slot's dedicated config dir once it exists" {
  _add_ee_slot
  _seed_dedicated_gh_config ee
  _mkrepo "$HOME/proj" "git@github.com-ee:owner/repo.git"
  cd "$HOME/proj"

  run "$REPO/bin/dot-git" gh-config-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/gh-ee" ]
}

@test "use reports the dedicated config and skips the global gh auth switch" {
  _add_ee_slot
  _seed_dedicated_gh_config ee
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"
  cd "$HOME/proj"

  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-use"* ]]
  [[ "$output" == *"gh-ee"* ]]

  run cat "$GH_LOG"
  [[ "$output" != *"auth switch"* ]]
}

@test "use still falls back to gh auth switch when no dedicated config exists" {
  _add_ee_slot
  _mkrepo "$HOME/proj" "https://github.com/owner/repo.git"
  cd "$HOME/proj"

  run "$REPO/bin/dot-git" use ee
  [ "$status" -eq 0 ]

  run cat "$GH_LOG"
  [[ "$output" == *"auth switch"* ]]
  [[ "$output" == *"workuser"* ]]
}

@test "add-identity registers the slot key via its own dedicated config when one already exists" {
  _seed_dedicated_gh_config newslot
  "$REPO/bin/dot-git" add-identity --name newslot --host github.com \
    --email me@newslot.test --github-user workuser --key "$HOME/seedkey" >/dev/null

  run cat "$GH_LOG"
  [[ "$output" == *"[$HOME/.config/gh-newslot] ssh-key add"* ]]
}

@test "add-identity registers via the ambient default config when no dedicated config exists yet" {
  "$REPO/bin/dot-git" add-identity --name newslot --host github.com \
    --email me@newslot.test --github-user workuser --key "$HOME/seedkey" >/dev/null

  run cat "$GH_LOG"
  [[ "$output" == *"[<default>] ssh-key add"* ]]
}
