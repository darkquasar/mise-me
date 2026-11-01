# Shared helpers for mise-me tasks. Source, do not execute.
#
# POSIX sh has no local variables, so each function prefixes its variables
# (for example _if_ in install_file) to avoid clobbering the caller's.

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

is_macos() { [ "$(uname -s)" = "Darwin" ]; }

# Base and extension names: lowercase letters, digits and dashes.
valid_name() {
  case $1 in
    '' | -* | *[!a-z0-9-]*) return 1 ;;
  esac
}

# The mise binary to call from tasks. ./bin/mise exports MISE_INSTALL_PATH;
# otherwise use the permanent install or whatever is on PATH.
if [ -n "${MISE_INSTALL_PATH:-}" ] && [ -x "$MISE_INSTALL_PATH" ]; then
  MISE=$MISE_INSTALL_PATH
elif [ -x "$HOME/.local/bin/mise" ]; then
  MISE=$HOME/.local/bin/mise
else
  MISE=mise
fi

# Where things go. mise and herdr follow XDG_CONFIG_HOME, and mise also
# honours MISE_CONFIG_DIR. starship does not use XDG (see bases/core).
config_home() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
mise_config_dir() { printf '%s' "${MISE_CONFIG_DIR:-$(config_home)/mise}"; }
mise_me_state() { printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/mise-me"; }

# home_dest REL: where a file at REL inside a home/ folder is installed.
home_dest() {
  case $1 in
    .config/mise/*) printf '%s/%s' "$(mise_config_dir)" "${1#.config/mise/}" ;;
    .config/*) printf '%s/%s' "$(config_home)" "${1#.config/}" ;;
    *) printf '%s/%s' "$HOME" "$1" ;;
  esac
}

# move_aside PATH: move a file, folder or symlink (even a dangling one) into
# its own new folder under ~/.local/state/mise-me/backups, keeping its path
# relative to $HOME. Backups never sit next to the original, so tools that
# read a whole folder (such as iTerm2 DynamicProfiles or conf.d) never see them.
move_aside() {
  _ma_target=$1
  [ -e "$_ma_target" ] || [ -L "$_ma_target" ] || return 0
  _ma_root="$(mise_me_state)/backups"
  mkdir -p "$_ma_root"
  _ma_slot=$(mktemp -d "$_ma_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
  case $_ma_target in
    "$HOME"/*) _ma_rel=${_ma_target#"$HOME"/} ;;
    *) _ma_rel=${_ma_target#/} ;;
  esac
  mkdir -p "$_ma_slot/$(dirname "$_ma_rel")"
  mv "$_ma_target" "$_ma_slot/$_ma_rel"
  log "backed up $_ma_target to $_ma_slot/$_ma_rel"
}

# install_file SRC DEST: copy SRC to DEST unless DEST already has the same
# content. Anything else at DEST is moved aside first, never overwritten.
install_file() {
  _if_src=$1
  _if_dest=$2
  if [ -f "$_if_dest" ] && [ ! -L "$_if_dest" ] && cmp -s "$_if_src" "$_if_dest"; then
    return 0
  fi
  mkdir -p "$(dirname "$_if_dest")"
  move_aside "$_if_dest"
  cp "$_if_src" "$_if_dest"
  log "installed $_if_dest"
}

# tree_files DIR OUT: write the files under DIR to OUT, one relative path
# per line, sorted. Fails if any part of DIR cannot be read. File names with
# newlines are not supported.
tree_files() {
  _tf_list=$(cd "$1" && find . -type f) || die "cannot read every file under $1"
  printf '%s\n' "$_tf_list" | sed 's#^\./##; /^$/d' | sort > "$2"
}

# tree_dests DIR OUT: like tree_files, but writes where each file installs.
tree_dests() {
  : > "$2"
  [ -d "$1" ] || return 0
  tree_files "$1" "$2.rel"
  while IFS= read -r _td_rel; do
    printf '%s\n' "$(home_dest "$_td_rel")" >> "$2"
  done < "$2.rel"
  rm -f "$2.rel"
}

# install_tree DIR: install every file under DIR (a mirror of $HOME) into
# place with install_file.
install_tree() {
  _it_dir=$1
  [ -d "$_it_dir" ] || return 0
  _it_list=$(mktemp)
  tree_files "$_it_dir" "$_it_list"
  while IFS= read -r _it_rel; do
    install_file "$_it_dir/$_it_rel" "$(home_dest "$_it_rel")"
  done < "$_it_list"
  rm -f "$_it_list"
}

# --- Machine state: which base and extensions this machine has -------------

recorded_base() {
  _rb="$(mise_me_state)/applied"
  if [ -f "$_rb" ]; then sed -n 's/^base=//p' "$_rb"; fi
}
recorded_with() {
  _rw="$(mise_me_state)/applied"
  if [ -f "$_rw" ]; then sed -n 's/^with=//p' "$_rw"; fi
}
# write_applied BASE WITH: record what this machine now has.
write_applied() {
  mkdir -p "$(mise_me_state)"
  printf 'base=%s\nwith=%s\n' "$1" "$2" > "$(mise_me_state)/applied.tmp"
  mv "$(mise_me_state)/applied.tmp" "$(mise_me_state)/applied"
}

# base_begin NAME / base_end NAME: called by every base's setup. When a base
# runs on its own (not through the router), refuse if this machine has a
# different base, and record the base on a machine that has none yet.
base_begin() {
  [ -z "${MISE_ME_ROUTED:-}" ] || return 0
  _bb=$(recorded_base)
  if [ -n "$_bb" ] && [ "$_bb" != "$1" ]; then
    die "this machine has base '$_bb'; to replace it run: ./bin/mise run setup $1 --switch"
  fi
}
base_end() {
  [ -z "${MISE_ME_ROUTED:-}" ] || return 0
  [ -n "$(recorded_base)" ] || write_applied "$1" ""
}

# Values from small TOML files (base.toml, ext.toml). Only one-line entries
# are supported: key = "value" and key = ["a", "b"].
toml_value() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$1" | head -n 1
}
toml_list() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "$1" |
    head -n 1 | tr ',' '\n' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^$/d'
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# fetch URL SHA256 OUT: download to OUT and check its SHA-256. Fails (and
# removes OUT) on any download error or checksum mismatch.
fetch() {
  _f_url=$1 _f_want=$2 _f_out=$3
  if ! curl -fsSL -o "$_f_out" "$_f_url"; then
    rm -f "$_f_out"
    die "download failed: $_f_url"
  fi
  _f_got=$(sha256_of "$_f_out")
  if [ "$_f_got" != "$_f_want" ]; then
    rm -f "$_f_out"
    die "checksum mismatch for $_f_url (expected $_f_want, got $_f_got)"
  fi
}

# --- Steps shared by every base ------------------------------------------

# step_self: make mise a permanent command at ~/.local/bin/mise.
step_self() {
  if _ss_existing=$(command -v mise 2>/dev/null); then
    log "mise already on PATH at $_ss_existing"
  elif [ -n "${MISE_INSTALL_PATH:-}" ] && [ -x "$MISE_INSTALL_PATH" ]; then
    # Running through ./bin/mise: keep the mise it downloaded.
    install_file "$MISE_INSTALL_PATH" "$HOME/.local/bin/mise"
    chmod +x "$HOME/.local/bin/mise"
  else
    die "no mise binary to install; run setup through ./bin/mise"
  fi
}

# step_tools: install every tool in the global mise config and its conf.d.
# Retries once: some installers (rustup) download without retrying, so one
# dropped connection would otherwise fail the whole setup.
step_tools() {
  (
    cd "$HOME"
    if ! "$MISE" install --yes; then
      warn "some tools failed to install; retrying once"
      "$MISE" install --yes
    fi
    "$MISE" ls --global
  )
}
