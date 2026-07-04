setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  export TERM=dumb
}

# `dot update sdkman` runs `sdk update` then `sdk upgrade` non-interactively.
# `sdk upgrade` prompts "Use prescribed default version(s)? (Y/n):" and reads
# stdin; the `sdk` dispatcher re-sources etc/config every call, so setting
# sdkman_auto_answer=true at runtime never sticks. Non-interactivity instead
# comes from the update running as a detached-stdin async command, so the prompt
# reads EOF (takes the default) rather than consuming the caller's stdin.
@test "dot update sdkman runs update+upgrade and its prompt reads EOF, not our stdin" {
  local fake="$BATS_TEST_TMPDIR/sdkman"
  mkdir -p "$fake/bin"
  local marker="$BATS_TEST_TMPDIR/marker"
  # Fake `sdk`: record each subcommand, and on upgrade prompt by reading stdin —
  # exactly like the real "Use prescribed default version(s)?" prompt.
  cat >"$fake/bin/sdkman-init.sh" <<EOF
sdk() {
  printf 'cmd=%s\n' "\$1" >>"$marker"
  if [ "\$1" = upgrade ]; then
    if read -r ans; then printf 'prompt=[%s]\n' "\$ans" >>"$marker"
    else printf 'prompt=EOF\n' >>"$marker"; fi
  fi
}
EOF

  # Feed a sentinel on stdin: an interactive step would consume it.
  run env SDKMAN_DIR="$fake" bash "$REPO/bin/dot-update" sdkman <<< 'SENTINEL'
  [ "$status" -eq 0 ]
  grep -q 'cmd=update' "$marker"
  grep -q 'cmd=upgrade' "$marker"
  # The prompt hits EOF instead of reading 'SENTINEL'.
  grep -q 'prompt=EOF' "$marker"
  ! grep -q 'SENTINEL' "$marker"
}
