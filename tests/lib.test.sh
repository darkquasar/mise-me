# Tests for lib/common.sh: file installs, backups, downloads, shared steps.

fresh_home collision
printf a > "$work/a"; printf b > "$work/b"; printf c > "$work/c"
run sh -c ". '$repo/lib/common.sh'; install_file '$work/a' '$H/f'; install_file '$work/b' '$H/f'; install_file '$work/c' '$H/f'" >/dev/null 2>&1
check "install_file: two quick replacements keep both old versions" \
  '[ "$(backups -type f -name f -exec cat {} + | fold -w1 | sort | tr -d "\n")" = ab ]'

fresh_home dangling
ln -s "$H/nowhere" "$H/f"
run sh -c ". '$repo/lib/common.sh'; install_file '$work/a' '$H/f'" >/dev/null 2>&1
check "install_file: dangling symlink is backed up and replaced by a file" \
  '[ ! -L "$H/f" ] && [ "$(cat "$H/f")" = a ] && [ -n "$(backups -type l -name f)" ]'

fresh_home outside
mkdir -p "$H/profiles"; printf old > "$H/profiles/p.json"
run sh -c ". '$repo/lib/common.sh'; install_file '$work/a' '$H/profiles/p.json'" >/dev/null 2>&1
check "install_file: backups are kept outside the destination folder" \
  '[ "$(ls -A "$H/profiles")" = p.json ] && [ -n "$(backups -type f -name p.json)" ]'

fresh_home badsum
url=https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.tar.gz
run sh -c ". '$repo/lib/common.sh'; fetch '$url' 0000 '$H/out'" >/dev/null 2>&1; rc=$?
check "fetch: a checksum mismatch fails and leaves no file" '[ "$rc" -ne 0 ] && [ ! -e "$H/out" ]'

fresh_home self
mkdir -p "$H/.local/bin"; printf sentinel > "$H/.local/bin/mise"
run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'; step_self" >/dev/null 2>&1
check "step_self: a non-executable ~/.local/bin/mise is backed up, not overwritten" \
  '[ -x "$H/.local/bin/mise" ] && backups -type f -name mise -exec cat {} + | grep -q sentinel'

# install_tree maps a home/ mirror into place, honouring XDG and MISE_CONFIG_DIR.
tree="$work/tree"
mkdir -p "$tree/.config/mise/conf.d" "$tree/.config/herdr"
printf 'a\n' > "$tree/.zshrc"; printf 'b\n' > "$tree/.config/mise/config.toml"
printf 'c\n' > "$tree/.config/mise/conf.d/x.toml"; printf 'd\n' > "$tree/.config/herdr/config.toml"

fresh_home tree
run sh -c ". '$repo/lib/common.sh'; install_tree '$tree'" >/dev/null 2>&1
check "install_tree: default paths under ~/.config" \
  '[ -f "$H/.zshrc" ] && [ -f "$H/.config/mise/config.toml" ] && [ -f "$H/.config/mise/conf.d/x.toml" ] && [ -f "$H/.config/herdr/config.toml" ]'

fresh_home xdg
run XDG_CONFIG_HOME="$H/xdg" sh -c ". '$repo/lib/common.sh'; install_tree '$tree'" >/dev/null 2>&1
check "install_tree: XDG_CONFIG_HOME is honoured for mise and herdr" \
  '[ -f "$H/xdg/mise/config.toml" ] && [ -f "$H/xdg/herdr/config.toml" ] && [ ! -e "$H/.config" ]'

fresh_home misecfg
run MISE_CONFIG_DIR="$H/m" sh -c ". '$repo/lib/common.sh'; install_tree '$tree'" >/dev/null 2>&1
check "install_tree: MISE_CONFIG_DIR is honoured, conf.d included" \
  '[ -f "$H/m/config.toml" ] && [ -f "$H/m/conf.d/x.toml" ]'

fresh_home unreadable
mkdir -p "$work/badtree/locked"; printf x > "$work/badtree/ok"; printf y > "$work/badtree/locked/f"
chmod 000 "$work/badtree/locked"
run sh -c ". '$repo/lib/common.sh'; install_tree '$work/badtree'" >/dev/null 2>&1; rc=$?
chmod 755 "$work/badtree/locked"
check "install_tree: a folder it cannot read makes it fail" '[ "$rc" -ne 0 ]'

fresh_home selfperm
mkdir -p "$H/.local/bin"; cp "$stub/fake-mise" "$H/.local/bin/mise"; chmod 644 "$H/.local/bin/mise"
run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'; step_self" >/dev/null 2>&1
check "step_self: an identical but non-executable copy becomes executable" '[ -x "$H/.local/bin/mise" ]'

fresh_home flaky
: > "$H/.fake-mise-fail-once"
run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'; step_tools" >/dev/null 2>&1; rc=$?
check "step_tools: retries once when an install fails" \
  '[ "$rc" -eq 0 ] && [ "$(grep -c "^install" "$H/.fake-mise.log")" = 2 ]'

# --- --terminal values -------------------------------------------------------
pt() { run sh -c ". '$repo/lib/common.sh'; parse_terminals '$1'" 2>/dev/null; }
check "parse_terminals: accepts names, aliases and both, in a fixed order" \
  '[ "$(pt terminal-app,iterm2)" = iterm2,terminal-app ] && [ "$(pt both)" = iterm2,terminal-app ] && [ "$(pt terminal)" = terminal-app ] && [ "$(pt none)" = none ] && [ "$(pt ask)" = ask ]'
check "parse_terminals: refuses unknown names and empty values" \
  '! pt konsole >/dev/null && ! pt "" >/dev/null && ! pt "," >/dev/null'

# --- --prompt values ---------------------------------------------------------
pp() { run sh -c ". '$repo/lib/common.sh'; parse_prompt '$1'" 2>/dev/null; }
check "parse_prompt: accepts pixel-gem, tokyo-night and the four catppuccin flavours" \
  'for t in pixel-gem tokyo-night catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha; do [ "$(pp $t)" = $t ] || exit 1; done'
check "parse_prompt: refuses unknown names, partial names and empty values" \
  '! pp neon >/dev/null && ! pp catppuccin >/dev/null && ! pp "" >/dev/null && ! pp "pixel-gem catppuccin-mocha" >/dev/null'

# --- next steps ---------------------------------------------------------------
fresh_home nextsteps
out=$(run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'
  next_steps_reset
  next_step 'Reload your shell' '\$ exec zsh' 'or open a new tab'
  next_step 'Reload your shell' '\$ exec zsh'
  next_step 'Sign in' '\$ sbx login'
  next_note 'a note'
  next_steps_show" 2>&1)
check "next steps: numbered, with commands and notes, repeats dropped" \
  'printf "%s\n" "$out" | grep -qx "1. Reload your shell" && printf "%s\n" "$out" | grep -qx "   \$ exec zsh" && printf "%s\n" "$out" | grep -qx "2. Sign in" && printf "%s\n" "$out" | grep -qx "a note" && [ "$(printf "%s\n" "$out" | grep -c Reload)" -eq 1 ]'
check "next steps: no colour codes when the output is not a terminal" '! printf "%s" "$out" | grep -q "$(printf "\033")"'
check "next steps: the list is deleted once shown" '[ ! -e "$H/.local/state/mise-me/next-steps" ]'

# --- step_tools and shims -------------------------------------------------------
fresh_home shims
sh_dir="$H/.local/share/mise/shims"
mkdir -p "$sh_dir" "$H/.local/bin"
cp "$stub/fake-mise" "$H/.local/bin/mise"
ln -s "$H/.local/share/mise/bootstrap/mise-2026.1.1" "$sh_dir/jq"
ln -s "$H/.local/bin/mise" "$sh_dir/rg"
run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'; step_tools" >/dev/null 2>&1; rc=$?
check "step_tools: shims made by the downloaded mise are removed and rebuilt" \
  '[ "$rc" -eq 0 ] && [ ! -e "$sh_dir/jq" ] && [ ! -L "$sh_dir/jq" ] && grep -qx reshim "$H/.fake-mise.log"'
check "step_tools: other shims are left alone" '[ -L "$sh_dir/rg" ]'
: > "$H/.fake-mise.log"
run MISE_INSTALL_PATH="$stub/fake-mise" sh -c ". '$repo/lib/common.sh'; step_tools" >/dev/null 2>&1
check "step_tools: no reshim when there is nothing to fix" '! grep -qx reshim "$H/.fake-mise.log"'

# --- task files ----------------------------------------------------------------
# mise reads every comment line starting with "#MISE"/"# MISE" (and USAGE) as
# task config, so prose comments must not start with those words.
bad=$(grep -nE '^#[[:space:]]+(MISE|USAGE)|^#(MISE|USAGE)[^ ]' "$repo"/mise-tasks/* "$repo"/bases/*/mise-tasks/* 2>/dev/null)
check "task files: no comment that mise would misread as task config" '[ -z "$bad" ]'
