# Tests for the core base: zsh plugin downloads and the setup preflight.

core="$repo/bases/core"
plugins=.local/share/zsh/plugins

fresh_home keep
mkdir -p "$H/$plugins/zsh-autosuggestions"; printf mine > "$H/$plugins/zsh-autosuggestions/sentinel"
run sh "$core/mise-tasks/zsh-plugins" >/dev/null 2>&1
check "zsh-plugins: an existing unmanaged plugin folder is backed up" \
  '[ -f "$H/$plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && [ -n "$(backups -type f -name sentinel)" ]'

fresh_home curlfail
mkdir -p "$H/$plugins/zsh-autosuggestions"; printf mine > "$H/$plugins/zsh-autosuggestions/sentinel"
run CURL_FAIL=1 sh "$core/mise-tasks/zsh-plugins" >/dev/null 2>&1; rc=$?
check "zsh-plugins: a failed download exits non-zero" '[ "$rc" -ne 0 ]'
check "zsh-plugins: a failed download leaves the existing folder untouched" \
  '[ -f "$H/$plugins/zsh-autosuggestions/sentinel" ]'

fresh_home rerun
run sh "$core/mise-tasks/zsh-plugins" >/dev/null 2>&1
run CURL_FAIL=1 sh "$core/mise-tasks/zsh-plugins" >/dev/null 2>&1; rc=$?
check "zsh-plugins: a second run needs no download" '[ "$rc" -eq 0 ]'

# Preflight: a PATH with the basics but no zsh, and a uname we control.
bare="$work/bare"
mkdir -p "$bare"
for c in sh cat date mkdir dirname curl tar; do ln -sf "$(command -v $c)" "$bare/$c"; done
printf '#!/bin/sh\n: > "$HOME/mise-was-called"\n' > "$work/marker-mise"; chmod +x "$work/marker-mise"
fake_uname() { printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; esac\n' "$1" "$2" > "$bare/uname"; chmod +x "$bare/uname"; }

fresh_home nozsh
fake_uname Linux x86_64
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$core/mise-tasks/setup" >/dev/null 2>&1; rc=$?
check "core setup: stops before changing anything when zsh is missing" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'

fresh_home intel
fake_uname Darwin x86_64
ln -sf "$(command -v zsh || echo /bin/zsh)" "$bare/zsh"
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$core/mise-tasks/setup" >/dev/null 2>&1; rc=$?
check "core setup: stops before changing anything on an Intel Mac" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'
rm -f "$bare/zsh"
