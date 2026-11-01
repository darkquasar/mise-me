# Tests for the root tasks: new-base, list and the setup router.
# They run against a copy of the repo with two throwaway bases made from the
# template, and a fake mise that runs base tasks without installing anything.

fix="$work/fixture"
mkdir -p "$fix"
(cd "$repo" && tar -cf - --exclude .git --exclude .serena .) | (cd "$fix" && tar -xf -)
newbase() { env -i HOME="$work" PATH="/usr/bin:/bin" usage_name="$1" sh "$fix/mise-tasks/new-base"; }

# --- new-base -----------------------------------------------------------
newbase alpha >/dev/null 2>&1; rc_a=$?
newbase beta >/dev/null 2>&1
check "new-base: creates a base from the template" \
  '[ "$rc_a" -eq 0 ] && [ -x "$fix/bases/alpha/mise-tasks/setup" ] && grep -q alpha "$fix/bases/alpha/base.toml"'
newbase alpha >/dev/null 2>&1; rc=$?
check "new-base: refuses a name that already exists" '[ "$rc" -ne 0 ]'
newbase "Bad Name" >/dev/null 2>&1; rc1=$?
newbase _hidden >/dev/null 2>&1; rc2=$?
check "new-base: refuses invalid names" '[ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ ! -d "$fix/bases/_hidden" ]'

# --- fixture extensions -------------------------------------------------
zconf=".config/zsh/conf.d"
mconf=".config/mise/conf.d"
# make_ext DIR WORKS_WITH FILE...: an extension shipping the given home files.
make_ext() {
  _d=$1 _w=$2; shift 2
  mkdir -p "$_d/home"
  if [ -n "$_w" ]; then
    printf 'description = "test"\nworks_with = [%s]\n' "$_w" > "$_d/ext.toml"
  else
    printf 'description = "test"\n' > "$_d/ext.toml"
  fi
  for _f in "$@"; do
    mkdir -p "$(dirname "$_d/home/$_f")"
    printf '# %s from %s\n' "$_f" "$(basename "$_d")" > "$_d/home/$_f"
  done
}
make_ext "$fix/bases/alpha/extensions/extra" "" "$zconf/extra.zsh" "$zconf/shared.zsh"
make_ext "$fix/bases/alpha/extensions/morph" "" "$zconf/morph-a.zsh"
make_ext "$fix/extensions/onlyalpha" '"alpha"' "$mconf/onlyalpha.toml"
make_ext "$fix/extensions/clash" '"alpha"' ".zshrc"
make_ext "$fix/extensions/dup" '"alpha"' "$zconf/extra.zsh"
make_ext "$fix/extensions/failer" '"alpha"' "$mconf/failme.toml"
# beta ships, as a base file, a path that alpha's "extra" extension also uses.
mkdir -p "$fix/bases/beta/home/$zconf"
printf 'from beta\n' > "$fix/bases/beta/home/$zconf/shared.zsh"

# route BASE [WITH [SWITCH]]: run the router; WITH is only passed when given,
# like mise does when --with is left out.
route() {
  if [ $# -ge 2 ]; then
    run MISE_INSTALL_PATH="$stub/fake-mise" usage_base="$1" usage_with="$2" \
      usage_switch="${3:-}" sh "$fix/mise-tasks/setup"
  else
    run MISE_INSTALL_PATH="$stub/fake-mise" usage_base="${1:-}" sh "$fix/mise-tasks/setup"
  fi
}
state() { cat "$H/.local/state/mise-me/applied" 2>/dev/null; }
untouched() { [ -z "$(ls -A "$H")" ]; }

# --- list ---------------------------------------------------------------
out=$(env -i HOME="$work" PATH=/usr/bin:/bin sh "$fix/mise-tasks/list" 2>&1)
check "list: shows bases with their extensions and the shared ones" \
  'printf "%s" "$out" | grep -q alpha && printf "%s" "$out" | grep -q extra && printf "%s" "$out" | grep -q core && printf "%s" "$out" | grep -q agents && printf "%s" "$out" | grep -q onlyalpha'
check "list: hides the template" '! printf "%s" "$out" | grep -q _template'

# --- validation happens before any change -------------------------------
fresh_home nobase
route >/dev/null 2>&1; rc=$?
check "setup: with no base and nothing recorded it stops" '[ "$rc" -ne 0 ] && untouched'

fresh_home unknown
route nosuch >/dev/null 2>&1; rc=$?
check "setup: an unknown base stops before any change" '[ "$rc" -ne 0 ] && untouched'

fresh_home notallowed
route beta onlyalpha >/dev/null 2>&1; rc=$?
check "setup: a shared extension outside its works_with stops before any change" '[ "$rc" -ne 0 ] && untouched'

fresh_home private
route beta extra >/dev/null 2>&1; rc=$?
check "setup: another base's private extension stops before any change" '[ "$rc" -ne 0 ] && untouched'

fresh_home clash
route alpha clash >/dev/null 2>&1; rc=$?
check "setup: an extension shipping a base-owned file stops before any change" '[ "$rc" -ne 0 ] && untouched'

fresh_home overlap
route alpha extra,dup >/dev/null 2>&1; rc=$?
check "setup: two extensions claiming the same file stop before any change" '[ "$rc" -ne 0 ] && untouched'

fresh_home parse
route alpha "extra,," >/dev/null 2>&1; rc1=$?
route alpha "extra extra" >/dev/null 2>&1; rc2=$?
route alpha "," >/dev/null 2>&1; rc3=$?
check "setup: empty or malformed extension lists stop before any change" \
  '[ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$rc3" -ne 0 ] && untouched'

# --- a full lifecycle on one machine ------------------------------------
fresh_home life
route alpha extra,onlyalpha >/dev/null 2>&1; rc=$?
check "setup: base plus extensions installs everything" \
  '[ "$rc" -eq 0 ] && [ -f "$H/.zshrc" ] && [ -f "$H/$zconf/extra.zsh" ] && [ -f "$H/$mconf/onlyalpha.toml" ]'
check "setup: records the base and extensions" \
  'state | grep -qx "base=alpha" && state | grep -qx "with=extra,onlyalpha"'
check "setup: installs tools after the extension files are in place" \
  'grep "^install --yes" "$H/.fake-mise.log" | grep -q onlyalpha.toml'

route beta >/dev/null 2>&1; rc=$?
check "setup: refuses a different base without --switch" '[ "$rc" -ne 0 ] && state | grep -qx "base=alpha"'

: > "$H/.fake-mise.log"
route alpha extra >/dev/null 2>&1; rc=$?
check "setup: a dropped extension's files are moved to backups" \
  '[ "$rc" -eq 0 ] && [ ! -e "$H/$mconf/onlyalpha.toml" ] && [ -n "$(backups -name onlyalpha.toml)" ] && [ -f "$H/$zconf/extra.zsh" ]'
check "setup: tools are installed without the dropped extension" \
  '! grep "^install" "$H/.fake-mise.log" | grep -q onlyalpha.toml'
check "setup: the record follows the new extension list" 'state | grep -qx "with=extra"'

: > "$H/.fake-mise.log"
route >/dev/null 2>&1; rc=$?
check "setup: with no arguments re-applies the recorded setup" \
  '[ "$rc" -eq 0 ] && grep -q "^run setup" "$H/.fake-mise.log" && [ -f "$H/$zconf/extra.zsh" ] && state | grep -qx "with=extra"'

route beta "" true >/dev/null 2>&1; rc=$?
check "setup: --switch changes base and removes the old extensions" \
  '[ "$rc" -eq 0 ] && state | grep -qx "base=beta" && [ ! -e "$H/$zconf/extra.zsh" ] && [ -n "$(backups -name extra.zsh)" ]'
check "setup: --switch keeps a file the new base ships that an old extension also used" \
  '[ "$(cat "$H/$zconf/shared.zsh" 2>/dev/null)" = "from beta" ]'

# --- reconciling extension files ----------------------------------------
fresh_home clear
route alpha extra >/dev/null 2>&1
route "" "" >/dev/null 2>&1; rc=$?
check "setup: an explicit empty --with clears the extensions" \
  '[ "$rc" -eq 0 ] && state | grep -qx "with=" && [ ! -e "$H/$zconf/extra.zsh" ]'

fresh_home morph
route alpha morph >/dev/null 2>&1
mv "$fix/bases/alpha/extensions/morph/home/$zconf/morph-a.zsh" "$fix/bases/alpha/extensions/morph/home/$zconf/morph-b.zsh"
route alpha morph >/dev/null 2>&1; rc=$?
check "setup: a file an extension no longer ships is moved to backups" \
  '[ "$rc" -eq 0 ] && [ ! -e "$H/$zconf/morph-a.zsh" ] && [ -f "$H/$zconf/morph-b.zsh" ] && [ -n "$(backups -name morph-a.zsh)" ]'
route alpha "" >/dev/null 2>&1
check "setup: dropping that extension later removes its current file" '[ ! -e "$H/$zconf/morph-b.zsh" ]'

fresh_home interrupted
route alpha failer >/dev/null 2>&1; rc1=$?
route alpha >/dev/null 2>&1; rc2=$?
check "setup: files from a failed extension run are cleaned up by the next run" \
  '[ "$rc1" -ne 0 ] && [ "$rc2" -eq 0 ] && [ ! -e "$H/$mconf/failme.toml" ] && [ -n "$(backups -name failme.toml)" ] && state | grep -qx "with="'

# --- running a base on its own ------------------------------------------
fresh_home standalone
(cd "$fix/bases/alpha" && run MISE_INSTALL_PATH="$stub/fake-mise" sh ./mise-tasks/setup) >/dev/null 2>&1; rc=$?
check "base setup on its own records the base on a fresh machine" \
  '[ "$rc" -eq 0 ] && state | grep -qx "base=alpha"'
(cd "$fix/bases/beta" && run MISE_INSTALL_PATH="$stub/fake-mise" sh ./mise-tasks/setup) >/dev/null 2>&1; rc=$?
check "base setup on its own refuses when the machine has another base" \
  '[ "$rc" -ne 0 ] && state | grep -qx "base=alpha" && [ ! -e "$H/$zconf/shared.zsh" ]'

# --- the real repo -------------------------------------------------------
check "agents: claude and codex live in the agents extension, not in core" \
  '! grep -qE "^(claude|codex) " "$repo/bases/core/home/.config/mise/config.toml" && grep -qE "^claude " "$repo/extensions/agents/home/.config/mise/conf.d/agents.toml" && grep -qE "^codex " "$repo/extensions/agents/home/.config/mise/conf.d/agents.toml"'
check "core: iTerm2 is not installed automatically (unpinned download)" \
  '! grep -q "brew install" "$repo/bases/core/mise-tasks/terminal"'
