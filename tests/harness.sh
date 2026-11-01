# Shared test helpers. Sourced by tests/run.sh; not run directly.
# Provides: $repo, $work, $cache, $stub, fresh_home, run, check, backups.

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cache="${XDG_CACHE_HOME:-$HOME/.cache}/mise-me-tests"
mkdir -p "$cache"

pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

# Real plugin tarballs, fetched once, so checksum verification runs for real.
for url in \
  https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.tar.gz \
  https://github.com/zsh-users/zsh-syntax-highlighting/archive/refs/tags/0.8.0.tar.gz; do
  name=$(printf '%s' "$url" | sed 's#https://github.com/##; s#/#_#g')
  [ -s "$cache/$name" ] || /usr/bin/curl -fsSL -o "$cache/$name" "$url"
done

stub="$work/stub"
mkdir -p "$stub"

# Fake curl: supports `curl ... -o FILE URL`; CURL_FAIL=1 makes it fail like a 403.
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

# Fake mise: logs every call; `run TASK` executes ./mise-tasks/TASK like mise
# does from the current folder; everything else succeeds without doing work.
# `install` fails once if ~/.fake-mise-fail-once exists, and always while a
# conf.d/failme.toml is present.
cat > "$stub/fake-mise" <<'EOF'
#!/bin/sh
confd="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/conf.d"
case ${1:-} in
  install)
    # Log which conf.d files mise would see, so tests can check ordering.
    printf '%s [conf.d: %s]\n' "$*" "$(ls "$confd" 2>/dev/null | tr '\n' ' ')" >> "$HOME/.fake-mise.log"
    if [ -f "$HOME/.fake-mise-fail-once" ]; then rm -f "$HOME/.fake-mise-fail-once"; exit 1; fi
    [ ! -f "$confd/failme.toml" ] || exit 1 ;;
  *) printf '%s\n' "$*" >> "$HOME/.fake-mise.log" ;;
esac
case ${1:-} in
  run) shift; task=$1; shift; exec sh "./mise-tasks/$task" "$@" ;;
  exec) shift; [ "${1:-}" = -- ] && shift; exec "$@" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$stub/curl" "$stub/fake-mise"

fresh_home() {
  H="$work/home.$1"
  rm -rf "$H"
  mkdir -p "$H"
}
run() { env -i HOME="$H" PATH="$stub:/usr/bin:/bin:/usr/sbin:/sbin" "$@"; }
backups() { find "$H/.local/state/mise-me/backups" "$@" 2>/dev/null; }
