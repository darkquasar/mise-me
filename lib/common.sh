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

# backup_defaults DOMAIN: macOS. Save a copy of an app's settings (such as
# com.apple.Terminal) into its own folder under the backups, before changing
# them in place. Restore with: defaults import DOMAIN FILE
backup_defaults() {
  _bd_root="$(mise_me_state)/backups"
  mkdir -p "$_bd_root"
  _bd_slot=$(mktemp -d "$_bd_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
  defaults export "$1" "$_bd_slot/$1.plist" || die "could not back up the settings of $1"
  log "backed up $1 settings to $_bd_slot/$1.plist"
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
# Run on its own, a base also collects and shows its own next steps; under
# the router, the router does that once everything (extensions too) is done.
base_begin() {
  [ -z "${MISE_ME_ROUTED:-}" ] || return 0
  _bb=$(recorded_base)
  if [ -n "$_bb" ] && [ "$_bb" != "$1" ]; then
    die "this machine has base '$_bb'; to replace it run: ./bin/mise run setup $1 --switch"
  fi
  next_steps_reset
}
base_end() {
  [ -z "${MISE_ME_ROUTED:-}" ] || return 0
  [ -n "$(recorded_base)" ] || write_applied "$1" ""
  next_steps_show
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

# --- Talking to the person running setup ---------------------------------

# interactive: true when someone can answer a prompt (not CI, not piped).
interactive() { [ -t 0 ] && [ -t 2 ] && [ -z "${CI:-}" ]; }

# gum_bin: print the path of gum (installed through mise) if there is one.
# Callers fall back to plain prompts and text when it prints nothing.
gum_bin() {
  _gb=$(cd "$HOME" && "$MISE" which gum 2>/dev/null) || _gb=""
  if [ -z "$_gb" ] || [ ! -x "$_gb" ]; then
    _gb=$(command -v gum 2>/dev/null) || _gb=""
  fi
  printf '%s' "$_gb"
}

# confirm QUESTION: ask a yes/no question (gum when there is one). True for yes.
# Callers check `interactive` first; with nobody to answer this returns false.
confirm() {
  interactive || return 1
  _c_gum=$(gum_bin)
  if [ -n "$_c_gum" ]; then
    "$_c_gum" confirm "$1"
    return
  fi
  printf '\n%s [y/N] ' "$1" >&2
  read -r _c_answer || return 1
  case $_c_answer in [yY] | [yY][eE][sS]) return 0 ;; esac
  return 1
}

# parse_terminals VALUE: check a --terminal value and print it normalised:
# "ask", "none", or ghostty, iterm2 and/or terminal-app, comma-separated,
# in that order. "all" is all three; "both" is iTerm2 and Terminal.app.
terminals_usage="--terminal needs a value: ghostty, iterm2, terminal-app (comma-separated), all, none or ask"
parse_terminals() {
  case $1 in
    ask | none) printf '%s' "$1"; return 0 ;;
    '') die "$terminals_usage" ;;
  esac
  _pt_g="" _pt_i="" _pt_t=""
  for _pt in $(printf '%s' "$1" | tr ',' ' '); do
    case $_pt in
      ghostty) _pt_g=ghostty ;;
      iterm2 | iterm) _pt_i=iterm2 ;;
      terminal-app | terminal) _pt_t=terminal-app ;;
      both) _pt_i=iterm2 _pt_t=terminal-app ;;
      all) _pt_g=ghostty _pt_i=iterm2 _pt_t=terminal-app ;;
      *) die "unknown terminal '$_pt' in --terminal (use ghostty, iterm2, terminal-app, all, none or ask)" ;;
    esac
  done
  [ -n "$_pt_g$_pt_i$_pt_t" ] || die "$terminals_usage"
  _pt_out=""
  for _pt in $_pt_g $_pt_i $_pt_t; do _pt_out="${_pt_out:+$_pt_out,}$_pt"; done
  printf '%s' "$_pt_out"
}

# parse_prompt VALUE: check a --prompt value (a colour theme for the starship
# prompt, see bases/core/mise-tasks/prompt) and print it. pixel-gem is the
# default; tokyo-night is starship's preset of that name; the catppuccin ones
# are the four flavours of its powerline preset.
prompt_themes="pixel-gem tokyo-night catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha catppuccin-cool"
parse_prompt() {
  case " $prompt_themes " in
    *" $1 "*) [ -n "$1" ] ;;
    *) false ;;
  esac || die "unknown prompt theme '$1' (use one of: $(printf '%s' "$prompt_themes" | tr ' ' ','))"
  printf '%s' "$1"
}

# --- The "next steps" message shown when setup finishes -------------------
# Steps are collected in a file while setup runs (tasks run as separate
# processes), shown once at the end, then deleted.

next_steps_file() { printf '%s/next-steps' "$(mise_me_state)"; }
next_steps_reset() { mkdir -p "$(mise_me_state)"; : > "$(next_steps_file)"; }

# next_step TITLE [LINE...]: add a numbered step. A LINE starting with "$ "
# is a command to run; any other LINE is an explanation. Repeats are ignored.
next_step() {
  mkdir -p "$(mise_me_state)"
  _ns_f=$(next_steps_file)
  if [ -f "$_ns_f" ] && grep -Fxq -- "$(printf 'S\t%s' "$1")" "$_ns_f"; then
    return 0
  fi
  {
    printf 'S\t%s\n' "$1"
    shift
    for _ns_line in "$@"; do printf 'D\t%s\n' "$_ns_line"; done
  } >> "$_ns_f"
}

# next_note TEXT: an unnumbered line shown under the steps.
next_note() {
  mkdir -p "$(mise_me_state)"
  _nn_f=$(next_steps_file)
  if [ -f "$_nn_f" ] && grep -Fxq -- "$(printf 'N\t%s' "$1")" "$_nn_f"; then
    return 0
  fi
  printf 'N\t%s\n' "$1" >> "$_nn_f"
}

# next_steps_show: print the collected steps (in a gum box when possible),
# then delete them.
next_steps_show() {
  _nss_f=$(next_steps_file)
  [ -s "$_nss_f" ] || { rm -f "$_nss_f"; return 0; }
  _nss_colour=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then _nss_colour=1; fi
  _nss_body=$(awk -v colour="$_nss_colour" '
    BEGIN {
      FS = "\t"
      if (colour) { num = "\033[36m"; cmd = "\033[32m"; dim = "\033[2m"; off = "\033[0m" }
    }
    $1 == "S" { if (n++) print ""; printf "%s%d.%s %s\n", num, n, off, $2 }
    $1 == "D" {
      if (substr($2, 1, 2) == "$ ") printf "   %s%s%s\n", cmd, $2, off
      else printf "   %s%s%s\n", dim, $2, off
    }
    $1 == "N" { notes = notes "\n" dim $2 off }
    END { if (notes != "") printf "%s\n", notes }
  ' "$_nss_f")
  rm -f "$_nss_f"
  _nss_gum=""
  [ -z "$_nss_colour" ] || _nss_gum=$(gum_bin)
  printf '\n'
  if [ -n "$_nss_gum" ] &&
    "$_nss_gum" style --border rounded --border-foreground 6 --padding "1 2" \
      "$(printf '\033[36mNext steps\033[0m\n\n%s' "$_nss_body")" 2>/dev/null; then
    return 0
  fi
  printf '%s\n\n%s\n' "== Next steps ==========================================" "$_nss_body"
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
#
# It runs the permanent mise, not the one ./bin/mise downloaded: shims link to
# the mise that made them, and the downloaded one has a versioned name
# (bootstrap/mise-VERSION) that mise later refuses to manage ("not replacing
# unmanaged file in shims directory") and that a newer bin/mise stops using.
step_tools() {
  _st_mise=$MISE
  if [ -x "$HOME/.local/bin/mise" ]; then
    _st_mise=$HOME/.local/bin/mise
  elif _st_found=$(command -v mise 2>/dev/null); then
    _st_mise=$_st_found
  fi
  (
    cd "$HOME"
    if ! "$_st_mise" install --yes; then
      warn "some tools failed to install; retrying once"
      "$_st_mise" install --yes
    fi
    # Shims an earlier setup made with the downloaded mise: replace them.
    _st_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
    _st_old=""
    for _st_s in "$_st_shims"/*; do
      [ -L "$_st_s" ] || continue
      case $(readlink "$_st_s") in
        */bootstrap/mise-*) rm -f "$_st_s"; _st_old=1 ;;
      esac
    done
    if [ -n "$_st_old" ]; then
      "$_st_mise" reshim
      log "rebuilt mise shims that pointed at the downloaded mise"
    fi
    "$_st_mise" ls --global
  )
}
