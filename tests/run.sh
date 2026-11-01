#!/bin/sh
# Offline regression tests for the setup tasks. Each test runs against a
# throwaway HOME, with a fake curl that serves files from a local cache.
# Usage: sh tests/run.sh
# The first run downloads the two pinned zsh plugin tarballs into the cache.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cache="${XDG_CACHE_HOME:-$HOME/.cache}/mise-me-tests"
mkdir -p "$cache"

pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

# Real tarballs, fetched once, so checksum verification runs for real.
for url in \
  https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.tar.gz \
  https://github.com/zsh-users/zsh-syntax-highlighting/archive/refs/tags/0.8.0.tar.gz; do
  name=$(printf '%s' "$url" | sed 's#https://github.com/##; s#/#_#g')
  [ -s "$cache/$name" ] || /usr/bin/curl -fsSL -o "$cache/$name" "$url"
done

# Fake curl: supports `curl ... -o FILE URL`; CURL_FAIL=1 makes it fail like a 403.
stub="$work/stub"
mkdir -p "$stub"
cat > "$stub/curl" <<EOF
#!/bin/sh
[ "\${CURL_FAIL:-0}" = 1 ] && { echo "curl: (22) 403" >&2; exit 22; }
out=""
while [ \$# -gt 0 ]; do
  case \$1 in -o) out=\$2; shift 2 ;; -*) shift ;; *) url=\$1; shift ;; esac
done
name=\$(printf '%s' "\$url" | sed 's#https://github.com/##; s#/#_#g')
[ -f "$cache/\$name" ] || { echo "curl: (22) not cached: \$url" >&2; exit 22; }
if [ -n "\$out" ]; then cp "$cache/\$name" "\$out"; else cat "$cache/\$name"; fi
EOF
chmod +x "$stub/curl"

fresh_home() {
  H="$work/home.$1"
  rm -rf "$H"
  mkdir -p "$H"
}
run() { env -i HOME="$H" PATH="$stub:/usr/bin:/bin:/usr/sbin:/sbin" "$@"; }
backups() { find "$H/.local/state/mise-me/backups" "$@" 2>/dev/null; }

# --- install_file -------------------------------------------------------
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

# --- self ---------------------------------------------------------------
fresh_home self
mkdir -p "$H/.local/bin"; printf sentinel > "$H/.local/bin/mise"
printf '#!/bin/sh\necho fake-mise\n' > "$work/fake-mise"; chmod +x "$work/fake-mise"
run MISE_INSTALL_PATH="$work/fake-mise" sh "$repo/mise-tasks/self" >/dev/null 2>&1
check "self: a non-executable ~/.local/bin/mise is backed up, not overwritten" \
  '[ -x "$H/.local/bin/mise" ] && backups -type f -name mise -exec cat {} + | grep -q sentinel'

# --- dotfiles -----------------------------------------------------------
fresh_home xdg
run XDG_CONFIG_HOME="$H/xdg" sh "$repo/mise-tasks/dotfiles" >/dev/null 2>&1
check "dotfiles: XDG_CONFIG_HOME is honoured for mise and herdr" \
  '[ -f "$H/xdg/mise/config.toml" ] && [ -f "$H/xdg/herdr/config.toml" ] && [ ! -e "$H/.config/mise" ]'

fresh_home misecfg
run MISE_CONFIG_DIR="$H/m" sh "$repo/mise-tasks/dotfiles" >/dev/null 2>&1
check "dotfiles: MISE_CONFIG_DIR is honoured for the mise config" \
  '[ -f "$H/m/config.toml" ]'

# --- zsh-plugins --------------------------------------------------------
plugins=.local/share/zsh/plugins
fresh_home keep
mkdir -p "$H/$plugins/zsh-autosuggestions"; printf mine > "$H/$plugins/zsh-autosuggestions/sentinel"
run sh "$repo/mise-tasks/zsh-plugins" >/dev/null 2>&1
check "zsh-plugins: an existing unmanaged plugin folder is backed up" \
  '[ -f "$H/$plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && [ -n "$(backups -type f -name sentinel)" ]'

fresh_home curlfail
mkdir -p "$H/$plugins/zsh-autosuggestions"; printf mine > "$H/$plugins/zsh-autosuggestions/sentinel"
run CURL_FAIL=1 sh "$repo/mise-tasks/zsh-plugins" >/dev/null 2>&1; rc=$?
check "zsh-plugins: a failed download exits non-zero" '[ "$rc" -ne 0 ]'
check "zsh-plugins: a failed download leaves the existing folder untouched" \
  '[ -f "$H/$plugins/zsh-autosuggestions/sentinel" ]'

fresh_home rerun
run sh "$repo/mise-tasks/zsh-plugins" >/dev/null 2>&1
run CURL_FAIL=1 sh "$repo/mise-tasks/zsh-plugins" >/dev/null 2>&1; rc=$?
check "zsh-plugins: a second run needs no download" '[ "$rc" -eq 0 ]'

fresh_home badsum
url=https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.tar.gz
run sh -c ". '$repo/lib/common.sh'; fetch '$url' 0000 '$H/out'" >/dev/null 2>&1; rc=$?
check "fetch: a checksum mismatch fails and leaves no file" '[ "$rc" -ne 0 ] && [ ! -e "$H/out" ]'

# --- setup preflight ----------------------------------------------------
# A PATH that has the basics but no zsh, and a uname we control.
bare="$work/bare"
mkdir -p "$bare"
for c in sh cat date mkdir dirname curl tar; do ln -sf "$(command -v $c)" "$bare/$c"; done
printf '#!/bin/sh\n: > "$HOME/mise-was-called"\n' > "$work/marker-mise"; chmod +x "$work/marker-mise"
fake_uname() { printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; esac\n' "$1" "$2" > "$bare/uname"; chmod +x "$bare/uname"; }

fresh_home nozsh
fake_uname Linux x86_64
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$repo/mise-tasks/setup" >/dev/null 2>&1; rc=$?
check "setup: stops before changing anything when zsh is missing" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'

fresh_home intel
fake_uname Darwin x86_64
ln -sf "$(command -v zsh || echo /bin/zsh)" "$bare/zsh"
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$repo/mise-tasks/setup" >/dev/null 2>&1; rc=$?
check "setup: stops before changing anything on an Intel Mac" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
