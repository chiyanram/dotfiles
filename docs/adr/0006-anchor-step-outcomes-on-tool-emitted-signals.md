# Anchor step outcome classification on tool-emitted signals, not English words

`dot-update` and `dot-doctor` steps run a captured command and must classify
its outcome as failed/changed/ok. Three times now (#81 doctor's SSH check,
#83 Homebrew, #93 Neovim) a step used `grep` for English words like
"Error"/"Failed"/"not installed" against the tool's own chatty output, and
each time a benign line containing one of those words (a cask caveat, a git
commit subject, a plugin's own log text) flipped a successful run to
"failed" — or the mirror bug, a strong-looking word never appearing let a
real failure through.

Decided: a step's outcome must be decided from a signal the underlying tool
itself emits to mean "this failed/changed" — its process exit code, or (when
exit code isn't reliable, e.g. lazy.nvim's headless sync never exits non-zero
on a task error) a structural marker the tool only emits for that specific
outcome, such as an ANSI severity color it applies exclusively to
error-level messages, or a task/log line that is itself gated on the
underlying state actually changing. Never classify by scanning free-text
output for words that can appear in unrelated, benign contexts.

Each classifier is a small pure function (`_brew_update_outcome`,
`_nvim_update_outcome`, …) taking the exit status and captured log,
returning `failed`/`changed`/`ok`, unit-tested against both real and
benign-lookalike output.
