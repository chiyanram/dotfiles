#!/usr/bin/env bash
# Resilient dotfiles installer: every step is non-fatal and re-runnable.

set -Eeuo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
source "$DOTFILES/bin/lib/common.sh"

DOT="$DOTFILES/bin/dot"

PROFILE_FLAG=""
NON_INTERACTIVE=0

usage() {
  cat <<EOF
  $(fmt_key "Usage:") $(fmt_cmd "setup.sh") $(fmt_value "[options]")

  Resilient dotfiles installer. Every step is independent and non-fatal: a
  blocked step is skipped, the run always completes with a summary, and
  re-running is safe.

  Options:
    --profile <personal|work>  Set the machine profile (default: prompt, else personal)
    --non-interactive          Never prompt; skip steps that need input
    -n, --dry-run              List the steps that would run, without executing them
    -h, --help                 Show this help
EOF
}

# ask_yes_no <prompt> — always false under --non-interactive.
ask_yes_no() {
  [[ "$NON_INTERACTIVE" -eq 1 ]] && return 1
  local answer
  printf "%b" "$1 [y/N] "
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

profile_file() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"; }

# ── Steps: each returns 0 (ok) / STEP_SKIP_CODE (skip) / 1 (fail) ──

step_xcode() {
  if xcode-select -p &>/dev/null; then
    log_success "Xcode CLI tools already installed"
    return "$STEP_SKIP_CODE"
  fi
  log_info "Installing Xcode CLI tools..."
  xcode-select --install || return 1
  if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
    log_warning "Press any key after the installation finishes"
    read -r -n 1 -s
  fi
}

step_homebrew() {
  if command -v brew &>/dev/null; then
    log_success "Homebrew already installed"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" homebrew install || return 1
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

step_profile() {
  if [[ -z "$PROFILE_FLAG" && -f "$(profile_file)" ]]; then
    log_success "Profile already set: $(dot_profile)"
    if [[ -z "$(dot_config docker_runtime)" ]]; then
      "$DOT" profile set-config docker_runtime "$(dot_docker_runtime)" || return 1
    fi
    return "$STEP_SKIP_CODE"
  fi

  local profile
  if [[ -n "$PROFILE_FLAG" ]]; then
    profile="$PROFILE_FLAG"
  elif [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    profile="personal"
  else
    printf "Machine profile [1=personal (default), 2=work]: "
    local choice
    read -r choice
    case "$choice" in
      2) profile="work" ;;
      *) profile="personal" ;;
    esac
  fi

  "$DOT" profile set "$profile" || return 1
  if [[ -z "$(dot_config docker_runtime)" ]]; then
    "$DOT" profile set-config docker_runtime "$(dot_docker_runtime)" || return 1
  fi
  log_info "Profile: $profile · docker runtime: $(dot_docker_runtime)"
}

step_ssh() {
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    log_success "SSH key already exists (~/.ssh/id_ed25519)"
    return "$STEP_SKIP_CODE"
  fi
  if ! ask_yes_no "Generate a new SSH key?"; then
    log_info "Skipping — generate later: ssh-keygen -t ed25519"
    return "$STEP_SKIP_CODE"
  fi
  local ssh_email
  printf "Email for SSH key: "
  read -r ssh_email
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519" || return 1
  # macOS launchd runs ssh-agent; --apple-use-keychain persists the key across
  # reboots. No `eval "$(ssh-agent -s)"` — that starts a redundant in-process agent.
  ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" ||
    log_warning "ssh-add failed — retry: ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    if ask_yes_no "Add this key to GitHub via gh?"; then
      gh ssh-key add "$HOME/.ssh/id_ed25519.pub" ||
        log_warning "gh ssh-key add failed — add it manually below"
    fi
  fi
  log_info "If not added above, add this public key to GitHub → Settings → SSH Keys:"
  cat "$HOME/.ssh/id_ed25519.pub"
  if command -v pbcopy &>/dev/null; then
    pbcopy <"$HOME/.ssh/id_ed25519.pub"
    log_info "Public key copied to clipboard"
  fi
  log_warning "Press any key after the key is on GitHub"
  read -r -n 1 -s
}

step_brew_bundle() {
  if ! command -v brew &>/dev/null; then
    log_warning "Homebrew not available — skipping bundle"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" homebrew bundle || return 1
}

step_link() {
  "$DOT" backup -v || true
  "$DOT" link all -v || return 1
}

step_shell() {
  "$DOT" shell change || return 1
}

step_git() {
  if [[ -f "$HOME/.gitconfig-local" ]]; then
    log_success "Git identity already configured (~/.gitconfig-local)"
    return "$STEP_SKIP_CODE"
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    log_info "Skipping git identity (non-interactive)"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" git setup || return 1
}

step_macos() {
  if ! ask_yes_no "Apply recommended macOS defaults?"; then
    log_info "Skipping — run 'dot macos defaults' later"
    return "$STEP_SKIP_CODE"
  fi
  "$DOT" macos defaults || return 1
}

configure_sdkman_auto_env() {
  local cfg="${SDKMAN_CONFIG:-$HOME/.sdkman/etc/config}"
  [[ -f "$cfg" ]] || return 0
  if grep -q '^sdkman_auto_env=true$' "$cfg"; then
    return 0
  elif grep -q '^sdkman_auto_env=' "$cfg"; then
    # Portable in-place edit: BSD sed wants `-i ''`, GNU sed wants `-i` with no
    # arg. Sidestep the divergence with a temp file so this works under both.
    local tmp
    tmp="$(mktemp)"
    sed 's/^sdkman_auto_env=.*/sdkman_auto_env=true/' "$cfg" >"$tmp" && mv "$tmp" "$cfg"
  else
    printf 'sdkman_auto_env=true\n' >>"$cfg"
  fi
  log_success "SDKMAN auto-env enabled (.sdkmanrc auto-applies on cd)"
}

# run_sdk <args...> — run `sdk <args...>` in a PATH-bash subprocess, TTY attached.
# Never `source` sdkman-init.sh into this process: setup.sh lives its whole life
# under system bash 3.2 with `set -u`, and the init script both expands unset
# vars (SDKMAN_CANDIDATES_API — a set -u abort that kills the entire script, not
# just the step) and uses bash-4-only syntax (${var^^} in its path helpers).
run_sdk() {
  bash -c 'source "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh" && sdk "$@"' sdk "$@"
}

step_sdkman() {
  if [[ -d "$HOME/.sdkman" ]]; then
    log_success "SDKMAN already installed"
    configure_sdkman_auto_env
    return "$STEP_SKIP_CODE"
  fi
  if ! ask_yes_no "Install SDKMAN (Java, Gradle, Maven manager)?"; then
    log_info "Skipping — install later: curl -s https://get.sdkman.io | bash"
    return "$STEP_SKIP_CODE"
  fi
  # SDKMAN's installer and `sdk` need bash >= 4. Probe the bash on PATH (what the
  # install pipe below runs under) — NOT $BASH_VERSINFO: this script keeps running
  # under system bash 3.2 for its whole life even after Homebrew installs bash 5.x.
  local path_bash_major
  path_bash_major="$(bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
  if [[ "$path_bash_major" -lt 4 ]]; then
    log_warning "SDKMAN needs bash >= 4 (PATH bash is $path_bash_major); install Homebrew's bash first, then: curl -s https://get.sdkman.io | bash"
    return "$STEP_SKIP_CODE"
  fi
  curl -fsSL --connect-timeout 10 --retry 2 https://get.sdkman.io | bash || return 1
  # Mandatory JVM toolchain — `dot doctor` treats these as required. `sdk install`
  # is idempotent (a present candidate is a no-op), so re-running setup is safe.
  local sdk_candidate
  for sdk_candidate in java gradle maven mvnd kotlin; do
    log_info "Installing $sdk_candidate via SDKMAN..."
    run_sdk install "$sdk_candidate" ||
      log_warning "sdk install $sdk_candidate failed — retry later: sdk install $sdk_candidate"
  done
  configure_sdkman_auto_env
  return 0 # per-candidate failures are warnings; the step still completes
}

step_doctor() {
  # Informational — doctor's exit code reflects post-install gaps, not a setup
  # failure, so this step never "fails"; it just surfaces a warning.
  if ! "$DOT" doctor; then
    log_warning "Health check found gaps — review the output above (run: dot doctor)"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ -z "${2:-}" ]] && {
          log_error "--profile requires an argument (personal or work)"
          exit 1
        }
        PROFILE_FLAG="$2"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      -n | --dry-run)
        # shellcheck disable=SC2034  # consumed by step() in common.sh (sourced), not within this file
        STEP_DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -n "$PROFILE_FLAG" && "$PROFILE_FLAG" != "personal" && "$PROFILE_FLAG" != "work" ]]; then
    log_error "Invalid --profile: $PROFILE_FLAG (must be personal or work)"
    exit 1
  fi

  fmt_title_border "Dotfiles Setup"
  echo

  step_init
  step "Xcode Command Line Tools" step_xcode
  step "Homebrew" step_homebrew
  step "Machine profile" step_profile
  step "SSH key" step_ssh
  step "Homebrew packages" step_brew_bundle
  step "Backup & link dotfiles" step_link
  step "Default shell" step_shell
  step "Git identity" step_git
  step "macOS defaults" step_macos
  step "SDKMAN & JVM tools" step_sdkman
  step "Health check" step_doctor

  local rc=0
  step_summary || rc=1
  echo
  fmt_title_border "Setup complete"
  log_info "Open a new terminal for all changes to take effect"
  log_info "Run 'dot doctor' anytime to verify your setup"
  return "$rc"
}

# Only run main when executed directly (sourcing for tests must not install anything).
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then main "$@"; fi
