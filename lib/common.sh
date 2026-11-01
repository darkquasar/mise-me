# Shared helpers for mise-me tasks. Source, do not execute.

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

is_macos() { [ "$(uname -s)" = "Darwin" ]; }

# The mise binary to call from tasks. ./bin/mise exports MISE_INSTALL_PATH;
# otherwise use the permanent install or whatever is on PATH.
if [ -n "${MISE_INSTALL_PATH:-}" ] && [ -x "$MISE_INSTALL_PATH" ]; then
  MISE=$MISE_INSTALL_PATH
elif [ -x "$HOME/.local/bin/mise" ]; then
  MISE=$HOME/.local/bin/mise
else
  MISE=mise
fi

# Where config files go. mise and herdr follow XDG_CONFIG_HOME, and mise also
# honours MISE_CONFIG_DIR. starship does not use XDG; see mise-tasks/prompt.
config_home() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
mise_config_dir() { printf '%s' "${MISE_CONFIG_DIR:-$(config_home)/mise}"; }

# move_aside PATH: move a file, folder or symlink (even a dangling one) into
# its own new folder under ~/.local/state/mise-me/backups, keeping its path
# relative to $HOME. Backups never sit next to the original, so tools that
# read a whole folder (such as iTerm2 DynamicProfiles) never see them.
move_aside() {
  target=$1
  [ -e "$target" ] || [ -L "$target" ] || return 0
  state="${XDG_STATE_HOME:-$HOME/.local/state}/mise-me/backups"
  mkdir -p "$state"
  slot=$(mktemp -d "$state/$(date +%Y%m%d-%H%M%S).XXXXXX")
  case $target in
    "$HOME"/*) rel=${target#"$HOME"/} ;;
    *) rel=${target#/} ;;
  esac
  mkdir -p "$slot/$(dirname "$rel")"
  mv "$target" "$slot/$rel"
  log "backed up $target to $slot/$rel"
}

# install_file SRC DEST: copy SRC to DEST unless DEST already has the same
# content. Anything else at DEST is moved aside first, never overwritten.
install_file() {
  src=$1
  dest=$2
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  move_aside "$dest"
  cp "$src" "$dest"
  log "installed $dest"
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
  url=$1 want=$2 out=$3
  if ! curl -fsSL -o "$out" "$url"; then
    rm -f "$out"
    die "download failed: $url"
  fi
  got=$(sha256_of "$out")
  if [ "$got" != "$want" ]; then
    rm -f "$out"
    die "checksum mismatch for $url (expected $want, got $got)"
  fi
}
