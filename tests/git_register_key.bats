setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
  # Pin DOTFILES to this tree so dot-git sources THIS worktree's libs, not an
  # inherited main-checkout DOTFILES (which lacks changes under test).
  export DOTFILES="$REPO"
  DOTGIT="$REPO/bin/dot-git"
}

# --- Seam B: the pure registration-plan decision ---------------------------
# Source dot-git (guarded so main does not run) and call the pure planner.
plan() {
  run bash -c "source '$DOTGIT'; _register_key_plan \"\$@\"" _ "$@"
}

@test "plan: an authenticated gitlab CLI registers via glab" {
  plan gitlab.com true true
  [ "$status" -eq 0 ]
  [ "$output" = "gitlab" ]
}

@test "plan: an authenticated github CLI registers via gh" {
  plan github.com true true
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "plan: falls back to paste when the CLI is not authenticated" {
  plan gitlab.com true false
  [ "$output" = "paste" ]
}

@test "plan: falls back to paste when the CLI is not installed" {
  plan github.com false false
  [ "$output" = "paste" ]
}

@test "plan: an unknown host falls back to paste" {
  plan example.com true true
  [ "$output" = "paste" ]
}

# --- Seam D: `dot git register-key` drives the host CLI end to end ----------

teardown() {
  [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
  return 0
}

sandbox() {
  SANDBOX="$(mktemp -d)"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)"
  export HOME="$SANDBOX"
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAAFAKEKEYDATA me@host\n' >"$HOME/.ssh/id_ed25519.pub"
  STUBDIR="$SANDBOX/stubbin"
  mkdir -p "$STUBDIR"
  export STUB_LOG="$SANDBOX/calls.log"
  : >"$STUB_LOG"
  # ssh-keyscan emits a deterministic fake host key so host-key trust is offline.
  cat >"$STUBDIR/ssh-keyscan" <<'EOF'
#!/usr/bin/env bash
for h; do :; done
printf '%s ssh-ed25519 AAAAFAKEHOSTKEY\n' "$h"
EOF
  chmod +x "$STUBDIR/ssh-keyscan"
  # Stub pbcopy so the paste fallback never clobbers the real clipboard.
  printf '#!/usr/bin/env bash\ncat >/dev/null\n' >"$STUBDIR/pbcopy"
  chmod +x "$STUBDIR/pbcopy"
  PATH="$STUBDIR:$PATH"
}

# stub_cli <name> <auth-exit-code>: log every call; `<name> auth ...` exits with
# the given code so the wrapper's auth probe is deterministic.
stub_cli() {
  local name="$1" auth_exit="$2"
  cat >"$STUBDIR/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$STUB_LOG"
if [ "\$1" = "auth" ]; then exit $auth_exit; fi
exit 0
EOF
  chmod +x "$STUBDIR/$name"
}

@test "register-key on gitlab trusts the host and uploads auth+signing via glab" {
  sandbox
  stub_cli glab 0 # present and authenticated
  run "$REPO/bin/dot-git" register-key --host gitlab.com
  [ "$status" -eq 0 ]
  # host key trusted (offline, via the ssh-keyscan stub)
  run grep -c gitlab.com "$HOME/.ssh/known_hosts"
  [ "$output" -ge 1 ]
  # glab invoked to add the default key as auth_and_signing
  run cat "$STUB_LOG"
  [[ "$output" == *"glab ssh-key add $HOME/.ssh/id_ed25519.pub --title"* ]]
  [[ "$output" == *"--usage-type auth_and_signing"* ]]
}

@test "add-identity registers the new slot key on the host" {
  sandbox
  stub_cli glab 0
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig-global"
  # Adopt a passphrase-less seed key so ssh-keygen never prompts interactively.
  ssh-keygen -t ed25519 -N "" -C seed@test -f "$HOME/seedkey" >/dev/null 2>&1
  run "$REPO/bin/dot-git" add-identity --name work-gl --host gitlab.com \
    --email me@work.test --key "$HOME/seedkey"
  [ "$status" -eq 0 ]
  run cat "$STUB_LOG"
  [[ "$output" == *"glab ssh-key add $HOME/seedkey.pub --title"* ]]
  [[ "$output" == *"--usage-type auth_and_signing"* ]]
}

@test "register-key prints the key for manual paste when the CLI is unauthenticated" {
  sandbox
  stub_cli glab 1 # present but NOT authenticated
  run "$REPO/bin/dot-git" register-key --host gitlab.com
  [ "$status" -eq 0 ]
  # printed the public key for manual paste
  [[ "$output" == *"AAAAFAKEKEYDATA"* ]]
  # did NOT attempt an upload
  run cat "$STUB_LOG"
  [[ "$output" != *"ssh-key add"* ]]
}
