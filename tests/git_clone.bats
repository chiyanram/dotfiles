setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)" # resolve symlinks so include paths match
  export HOME="$SANDBOX"
  export XDG_CONFIG_HOME="$SANDBOX/.config"
  export DOTFILES="$REPO"
  export TERM=dumb
  # Make git use a clean global config (the committed one) under XDG.
  export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
  mkdir -p "$XDG_CONFIG_HOME/git"
  cp "$REPO/config/git/config" "$GIT_CONFIG_GLOBAL"
  git config -f "$HOME/.gitconfig-local" user.email "me@home.test"
  git config -f "$HOME/.gitconfig-local" user.name "Me Personal"
  # Pre-generate a throwaway passphrase-less key so tests never hit an interactive prompt.
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "seed@test" -f "$HOME/seedkey" >/dev/null 2>&1

  # A fake `gh` on PATH so add-identity's auto-register step never touches the
  # real gh (or its real auth state); irrelevant to clone itself.
  mkdir -p "$HOME/bin"
  cat >"$HOME/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$HOME/bin/gh"
  export PATH="$HOME/bin:$PATH"
}

teardown() { [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }

_add_ee_slot() {
  "$REPO/bin/dot-git" add-identity --name ee --host github.com \
    --email me@work.test --github-user workuser --key "$HOME/seedkey" >/dev/null
}

# A `git` stub that intercepts only `clone` (logging its argv) and execs the
# real git for everything else (add-identity still needs real git config).
_git_clone_stub_path() {
  local dir="$HOME/gitstub" real
  real="$(command -v git)"
  mkdir -p "$dir"
  cat >"$dir/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "clone" ]]; then
  printf '%s\n' "\$*" >>"$HOME/git-clone.log"
  exit 0
fi
exec "$real" "\$@"
EOF
  chmod +x "$dir/git"
  printf '%s\n' "$dir"
}

@test "clone builds the slot-aliased URL and invokes git clone" {
  _add_ee_slot
  local stub
  stub="$(_git_clone_stub_path)"

  run env PATH="$stub:$PATH" "$REPO/bin/dot-git" clone ee owner/repo
  [ "$status" -eq 0 ]

  run cat "$HOME/git-clone.log"
  [ "$output" = "clone git@github.com-ee:owner/repo" ]
}

@test "clone passes through extra git-clone args after the URL" {
  _add_ee_slot
  local stub
  stub="$(_git_clone_stub_path)"

  run env PATH="$stub:$PATH" "$REPO/bin/dot-git" clone ee owner/repo mydir --depth 1
  [ "$status" -eq 0 ]

  run cat "$HOME/git-clone.log"
  [ "$output" = "clone git@github.com-ee:owner/repo mydir --depth 1" ]
}

@test "clone errors clearly when the slot does not exist, without invoking git" {
  local stub
  stub="$(_git_clone_stub_path)"

  run env PATH="$stub:$PATH" "$REPO/bin/dot-git" clone ghost owner/repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"add-identity"* ]]
  [[ ! -f "$HOME/git-clone.log" ]]
}

@test "clone errors clearly when owner/repo is missing" {
  _add_ee_slot
  run "$REPO/bin/dot-git" clone ee
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "clone errors clearly when the slot is missing" {
  run "$REPO/bin/dot-git" clone
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
