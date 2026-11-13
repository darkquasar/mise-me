# Tests for the core base: zsh plugin downloads and the setup preflight.

core="$repo/bases/core"
plugins=.local/share/zsh/plugins

fresh_home keep
mkdir -p "$H/$plugins/zsh-autosuggestions"; printf mine > "$H/$plugins/zsh-autosuggestions/sentinel"
run sh "$core/mise-tasks/zsh-plugins" >/dev/null 2>&1
check "zsh-plugins: an existing unmanaged plugin folder is backed up" \
  '[ -f "$H/$plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && [ -n "$(backups -type f -name sentinel)" ]'
check "zsh-plugins: fzf-tab is installed with the others" '[ -f "$H/$plugins/fzf-tab/fzf-tab.plugin.zsh" ]'

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
printf '#!/bin/sh\nexit 0\n' > "$bare/apt-get"; chmod +x "$bare/apt-get"
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$core/mise-tasks/setup" >/dev/null 2>"$work/nozsh.err"; rc=$?
check "core setup: stops before changing anything when zsh is missing" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'
check "core setup: the zsh hint names apt on a Debian-style machine" \
  'grep -q "sudo apt install zsh" "$work/nozsh.err"'
rm -f "$bare/apt-get"
printf '#!/bin/sh\nexit 0\n' > "$bare/dnf"; chmod +x "$bare/dnf"
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$core/mise-tasks/setup" >/dev/null 2>"$work/nozsh.err"; rc=$?
check "core setup: the zsh hint names dnf on a Fedora-style machine" \
  '[ "$rc" -ne 0 ] && grep -q "sudo dnf install zsh" "$work/nozsh.err"'
rm -f "$bare/dnf"

# --- A headless Linux run (the VM case): fake uname and starship, fake mise ---
# Everything that touches the network or the OS is a fake, so this checks the
# Linux path of setup itself: files land, tools are asked for, nothing macOS
# runs, and the next steps say what the VM still needs.
lhost="$work/lhost"
mkdir -p "$lhost"
printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo aarch64 ;; *) echo Linux ;; esac\n' > "$lhost/uname"
ln -sf "$(command -v zsh || echo /bin/zsh)" "$lhost/zsh"
# `starship preset NAME -o FILE`: for each preset, the lines the prompt task
# edits and checks. Its own folder, so the macOS run below can use it too.
fakestar="$work/fakestar"; mkdir -p "$fakestar"
cat > "$fakestar/starship" <<'EOS'
#!/bin/sh
out=""; prev=""
for a; do [ "$prev" = -o ] && out=$a; prev=$a; done
[ -n "$out" ] || exit 1
case $2 in
  pastel-powerline)
    { printf "format = '[ \342\231\245 \$time ](\$style)'\n"; printf 'style = "bg:#FCA17D"\nstyle = "bg:#86BBD8"\n'; } > "$out" ;;
  catppuccin-powerline)
    # FAKE_STARSHIP_LINE adds one line, for example a colour the preset did not use before.
    { printf "palette = 'catppuccin_mocha'\n"; printf '[](red)\\\nstyle = "bg:red fg:crust"\n'
      [ -z "${FAKE_STARSHIP_LINE:-}" ] || printf '%s\n' "$FAKE_STARSHIP_LINE"
      printf "success_symbol = '[\342\235\257](bold fg:green)'\nerror_symbol = '[\342\235\257](bold fg:red)'\n"
      for f in mocha frappe macchiato latte; do printf '[palettes.catppuccin_%s]\nred = "#f38ba8"\n' "$f"; done; } > "$out" ;;
  tokyo-night)
    printf 'format = """\n$time\\\n$character"""\n\n[time]\nstyle = "bg:#1d2230"\n' > "$out" ;;
  *) echo "fake starship: no preset $2" >&2; exit 1 ;;
esac
EOS
chmod +x "$lhost"/* "$fakestar"/*
# linux_setup VAR=value...: core setup as the router runs it (MISE_ME_ROUTED
# keeps the next-steps file for inspection instead of printing it).
linux_setup() {
  env -i HOME="$H" PATH="$lhost:$fakestar:$stub:/usr/bin:/bin" MISE_INSTALL_PATH="$stub/fake-mise" \
    MISE_ME_ROUTED=1 "$@" sh "$core/mise-tasks/setup" </dev/null >"$H/.out" 2>&1
}
lsteps() { cat "$H/.local/state/mise-me/next-steps" 2>/dev/null; }

fresh_home linuxvm
linux_setup SHELL=/bin/bash MISE_ME_PROMPT=tokyo-night; rc=$?
check "core setup on Linux: completes with the dotfiles, tools and prompt in place" \
  '[ "$rc" -eq 0 ] && [ -f "$H/.zshrc" ] && [ -f "$H/.config/mise/config.toml" ] && [ -f "$H/.config/starship.toml" ] && [ -f "$H/$plugins/fzf-tab/fzf-tab.plugin.zsh" ] && grep -q "^install --yes" "$H/.fake-mise.log"'
check "core setup on Linux: --prompt reaches the prompt step and is saved (the unattended VM command)" \
  'grep -q "bg:#1d2230" "$H/.config/starship.toml" && [ "$(cat "$H/.local/state/mise-me/prompt")" = tokyo-night ]'
check "core setup on Linux: skips the terminal step and touches nothing under ~/Library" \
  'grep -q "not macOS, skipping terminal setup" "$H/.out" && [ ! -d "$H/Library" ]'
check "core setup on Linux: a bash login shell gets a chsh step" \
  'lsteps | grep -q "Make zsh your login shell" && lsteps | grep -q "chsh -s"'
check "core setup on Linux: no sbx sign-in step, and a note on why sbx is missing" \
  '! lsteps | grep -q "sbx login" && lsteps | grep -q "Docker Sandboxes (sbx) is not installed on Linux"'
check "core setup on Linux: says the Nerd Font belongs on the machine you connect from" \
  'lsteps | grep -q "Nerd Font"'

fresh_home linuxzsh
linux_setup SHELL=/usr/bin/zsh; rc=$?
check "core setup on Linux: a zsh login shell gets no chsh step" \
  '[ "$rc" -eq 0 ] && ! lsteps | grep -q "login shell"'

# --- prompt: which colour theme, and remembering it -------------------------
# prompt_run [VAR=value...]: the prompt step alone, with the fake starship.
prompt_run() {
  env -i HOME="$H" PATH="$fakestar:$stub:/usr/bin:/bin" MISE_INSTALL_PATH="$stub/fake-mise" "$@" \
    sh "$core/mise-tasks/prompt" </dev/null >"$H/.out" 2>&1
}
starship_toml() { cat "$H/.config/starship.toml" 2>/dev/null; }
saved_prompt() { cat "$H/.local/state/mise-me/prompt" 2>/dev/null; }

fresh_home pdefault
prompt_run; rc=$?
check "prompt: with no choice, pixel-gem (pastel-powerline with the mise-me edits) and nothing saved" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^style = \"bg:#E78A4E fg:#282828\"$" && [ -z "$(saved_prompt)" ]'

fresh_home pmocha
prompt_run MISE_ME_PROMPT=catppuccin-mocha; rc=$?
check "prompt: catppuccin-mocha writes the catppuccin preset with the mocha palette and saves the choice" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^palette = '"'"'catppuccin_mocha'"'"'$" && [ "$(saved_prompt)" = catppuccin-mocha ]'
prompt_run; rc=$?
check "prompt: a re-run keeps the saved theme" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "catppuccin_mocha" && grep -q "saved choice" "$H/.out"'
prompt_run MISE_ME_PROMPT=catppuccin-latte; rc=$?
check "prompt: --prompt replaces the saved theme (latte picks the light palette)" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^palette = '"'"'catppuccin_latte'"'"'$" && ! starship_toml | grep -q "^palette = '"'"'catppuccin_mocha'"'"'$" && [ "$(saved_prompt)" = catppuccin-latte ]'
check "prompt: the replaced config is backed up" '[ -n "$(backups -type f -name starship.toml)" ]'
prompt_run MISE_ME_PROMPT=pixel-gem; rc=$?
check "prompt: back to pixel-gem by name" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "#E78A4E" && [ "$(saved_prompt)" = pixel-gem ]'

fresh_home ptokyo
prompt_run MISE_ME_PROMPT=tokyo-night; rc=$?
check "prompt: tokyo-night installs starship's preset unchanged and saves the choice" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "bg:#1d2230" && ! starship_toml | grep -q "palette\|#E78A4E" && [ "$(saved_prompt)" = tokyo-night ]'

fresh_home pflag
prompt_run usage_prompt=catppuccin-frappe; rc=$?
check "prompt: the task's own --prompt flag works when run on its own" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^palette = '"'"'catppuccin_frappe'"'"'$" && [ "$(saved_prompt)" = catppuccin-frappe ]'

fresh_home promptcool
prompt_run MISE_ME_PROMPT=catppuccin-cool; rc=$?
check "prompt: catppuccin-cool keeps the catppuccin layout with the cool palette and saves the choice" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^style = \"bg:red fg:crust\"$" && starship_toml | grep -q "^palette = '"'"'catppuccin_cool'"'"'$" && starship_toml | grep -q "^\[palettes\.catppuccin_cool\]$" && starship_toml | grep -q "^red = \"#cba6f7\"" && [ "$(saved_prompt)" = catppuccin-cool ]'
check "prompt: catppuccin-cool gives the failed-command arrow its own red" \
  'starship_toml | grep -q "^error_symbol = .*fg:error)" && starship_toml | grep -q "^error = \"#f38ba8\"" && starship_toml | grep -q "^success_symbol = .*fg:green)"'
# A colour the palette lacks, written any way starship accepts, stops setup and
# leaves the existing config exactly as it was.
for line in 'style = "bg:rosewater fg:crust"' '[](rosewater)\' '[x](bold fg:red2)'; do
  fresh_home promptcoolnew
  mkdir -p "$H/.config"; echo "mine" > "$H/.config/starship.toml"
  prompt_run MISE_ME_PROMPT=catppuccin-cool FAKE_STARSHIP_LINE="$line"; rc=$?
  check "prompt: catppuccin-cool stops, changing nothing, if the preset gains a colour its palette lacks: $line" \
    '[ "$rc" -ne 0 ] && [ "$(starship_toml)" = mine ] && [ -z "$(backups -type f)" ] && grep -q "catppuccin-cool.toml lacks" "$H/.out"'
done
# Things in a style that are not palette colours do not stop it.
fresh_home promptcoolok
prompt_run MISE_ME_PROMPT=catppuccin-cool FAKE_STARSHIP_LINE='[x](bold italic fg:#ffffff bg:prev_bg $style)'; rc=$?
check "prompt: catppuccin-cool accepts modifiers, hex colours and \$style in the preset" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "^palette = '"'"'catppuccin_cool'"'"'$"'

fresh_home pbad
prompt_run MISE_ME_PROMPT=neon; rc=$?
check "prompt: an unknown theme stops before writing or saving anything" \
  '[ "$rc" -ne 0 ] && [ -z "$(starship_toml)" ] && [ -z "$(saved_prompt)" ] && grep -q "unknown prompt theme" "$H/.out"'

fresh_home pstale
mkdir -p "$H/.local/state/mise-me"; echo neon > "$H/.local/state/mise-me/prompt"
prompt_run; rc=$?
check "prompt: a saved name that no longer exists falls back to pixel-gem" \
  '[ "$rc" -eq 0 ] && starship_toml | grep -q "#E78A4E"'

check "prompt: the theme list is the same everywhere it is spelled out" \
  'for t in $(sed -n "s/^prompt_themes=\"\(.*\)\"/\1/p" "$repo/lib/common.sh"); do grep -q "$t" "$repo/mise-tasks/setup" && grep -q "$t" "$core/mise-tasks/setup" && grep -q "$t" "$core/mise-tasks/prompt" && grep -q "$t" "$repo/README.md" || exit 1; done'

check "core config: Docker Sandboxes is limited to macOS (a VM has no KVM)" \
  'awk "/sbx-releases\"\]\$/{f=1} f && /^os = /{print; exit}" "$core/home/.config/mise/config.toml" | grep -q "^os = \[\"macos\"\]" && ! grep -q "DockerSandboxes-linux" "$core/home/.config/mise/config.toml"'

fresh_home intel
fake_uname Darwin x86_64
ln -sf "$(command -v zsh || echo /bin/zsh)" "$bare/zsh"
env -i HOME="$H" PATH="$bare" MISE_INSTALL_PATH="$work/marker-mise" sh "$core/mise-tasks/setup" >/dev/null 2>&1; rc=$?
check "core setup: stops before changing anything on an Intel Mac" \
  '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$H")" ]'
rm -f "$bare/zsh"

# --- terminal: which apps get set up, and how --------------------------------
# Fakes, so nothing real is touched: uname says macOS; pgrep "finds" the apps
# named in FAKE_RUNNING; osascript prints FAKE_TA_STATUS for `status` and
# logs every call; open logs what it would open; defaults keeps iTerm2 keys as
# files under ~/.fake-defaults.
tstub="$work/tstub"
mkdir -p "$tstub"
printf '#!/bin/sh\ncase "$1" in -s) echo Darwin ;; -m) echo arm64 ;; *) echo Darwin ;; esac\n' > "$tstub/uname"
cat > "$tstub/pgrep" <<'EOS'
#!/bin/sh
# Without -a, macOS pgrep skips its ancestors: setup runs inside the app.
case $1 in -*a*) ;; *) exit 1 ;; esac
for a; do name=$a; done
case " ${FAKE_RUNNING:-} " in *" $name "*) exit 0 ;; esac
exit 1
EOS
cat > "$tstub/osascript" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/.osascript.log"
case "$*" in
  *" status "*) printf '%s\n' "${FAKE_TA_STATUS:-Basic	missing}" ;;
esac
exit 0
EOS
cat > "$tstub/defaults" <<'EOS'
#!/bin/sh
d="$HOME/.fake-defaults"
case $1 in
  read) [ -f "$d/$3" ] && cat "$d/$3" ;;
  write) mkdir -p "$d"; printf '%s\n' "$5" > "$d/$3" ;;
  export) printf "exported %s\n" "$2" > "$3" ;;
esac
EOS
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$HOME/.open.log"\n' > "$tstub/open"
# Downloads: sha256sum reports FAKE_SHA when set (so a fake download passes
# the pinned checksum); hdiutil "mounts" a disk image by creating Ghostty.app
# under the mount point, and like the real one fails to detach what is not
# mounted; ditto copies, or "unzips" an iTerm.app.
cat > "$tstub/sha256sum" <<'EOS'
#!/bin/sh
if [ -n "${FAKE_SHA:-}" ]; then printf '%s  %s\n' "$FAKE_SHA" "$1"; else exec /usr/bin/shasum -a 256 "$@"; fi
EOS
cat > "$tstub/hdiutil" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/.hdiutil.log"
mp=""; prev=""
for a; do [ "$prev" = -mountpoint ] && mp=$a; prev=$a; done
case $1 in
  attach) mkdir -p "$mp/Ghostty.app"; : > "$mp/.mounted" ;;
  detach) for a; do mp=$a; done; [ -f "$mp/.mounted" ] || { echo "hdiutil: detach failed - No such file or directory" >&2; exit 1; }; rm -rf "$mp/.mounted" "$mp/Ghostty.app" ;;
esac
EOS
cat > "$tstub/ditto" <<'EOS'
#!/bin/sh
case $1 in -xk) mkdir -p "$3/iTerm.app" ;; *) cp -R "$1" "$2" ;; esac
EOS
chmod +x "$tstub"/*
dl="$work/dl"; mkdir -p "$dl"
printf 'not really a disk image\n' > "$dl/https:__release.files.ghostty.org_1.4.0_Ghostty.dmg"
printf 'not really a zip\n' > "$dl/https:__iterm2.com_downloads_stable_iTerm2-3_7_6.zip"
ghostty_sha=$(sed -n 's/^ghostty_sha=//p' "$core/mise-tasks/terminal")
iterm_sha=$(sed -n 's/^iterm_sha=//p' "$core/mise-tasks/terminal")
apps="$work/apps"
mkdir -p "$apps/none" "$apps/with/iTerm.app" "$apps/with/Ghostty.app"
iprofile="Library/Application Support/iTerm2/DynamicProfiles/mise-me.json"
gconfig=".config/ghostty/config"

# term ARGS...: run the terminal task in $H with the fakes; ARGS are VAR=value.
term() {
  mkdir -p "$H/Library/Fonts"; : > "$H/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf"
  env -i HOME="$H" PATH="$tstub:$stub:/usr/bin:/bin:/usr/sbin:/sbin" \
    MISE_INSTALL_PATH="$stub/fake-mise" MISE_ME_APP_DIRS="$apps/none" "$@" \
    sh "$core/mise-tasks/terminal" </dev/null >"$H/.out" 2>&1
}
steps() { cat "$H/.local/state/mise-me/next-steps" 2>/dev/null; }
saved() { cat "$H/.local/state/mise-me/terminals" 2>/dev/null; }
ascalls() { cat "$H/.osascript.log" 2>/dev/null; }
opened() { cat "$H/.open.log" 2>/dev/null; }

# The whole core setup on a "Mac" (the terminal fakes above, no app chosen).
fresh_home macsteps
mkdir -p "$H/Library/Fonts"; : > "$H/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf"
env -i HOME="$H" PATH="$tstub:$fakestar:$stub:/usr/bin:/bin:/usr/sbin:/sbin" MISE_INSTALL_PATH="$stub/fake-mise" \
  MISE_ME_ROUTED=1 MISE_ME_TERMINALS=none SHELL=/bin/zsh sh "$core/mise-tasks/setup" </dev/null >"$H/.out" 2>&1; rc=$?
check "core setup on macOS: keeps the sbx sign-in step and adds no Linux notes or chsh step" \
  '[ "$rc" -eq 0 ] && steps | grep -q "sbx login" && ! steps | grep -q "not installed on Linux" && ! steps | grep -q "login shell"'

fresh_home tdetect
term TERM_PROGRAM=Apple_Terminal; rc=$?
check "terminal: with nobody to ask, sets up the app setup runs in" \
  '[ "$rc" -eq 0 ] && ascalls | grep -q " apply " && [ ! -e "$H/$iprofile" ]'
check "terminal: a detected choice is not saved (a later interactive run still asks)" '[ -z "$(saved)" ]'

check "terminal: with nobody to ask, Ghostty is detected from TERM_PROGRAM" \
  'fresh_home tdetectg; term TERM_PROGRAM=ghostty MISE_ME_APP_DIRS="$apps/with"; [ -f "$H/$gconfig" ] && [ -z "$(ascalls)" ] && [ ! -e "$H/$iprofile" ]'

fresh_home tnoiterm
term MISE_ME_TERMINALS=iterm2; rc=$?
check "terminal: iterm2 without iTerm2 installed adds the profile and an install step (no download without a yes)" \
  '[ "$rc" -eq 0 ] && [ -f "$H/$iprofile" ] && steps | grep -q "Install iTerm2" && [ ! -d "$H/.fake-defaults" ] && [ ! -d "$H/Applications" ]'
check "terminal: an explicit choice is saved" '[ "$(saved)" = iterm2 ]'
check "terminal: iterm2 alone leaves Terminal.app alone" '[ -z "$(ascalls)" ]'

fresh_home tiset
mkdir -p "$H/.fake-defaults"; echo x > "$H/.fake-defaults/New Bookmarks"
term MISE_ME_TERMINALS=iterm2 MISE_ME_APP_DIRS="$apps/with"; rc=$?
check "terminal: a closed iTerm2 gets mise-me as its default profile" \
  '[ "$rc" -eq 0 ] && [ "$(cat "$H/.fake-defaults/Default Bookmark Guid")" = mise-me-profile ] && ! steps | grep -q iTerm2'
check "terminal: iTerm2's settings are backed up before they are changed" \
  '[ -n "$(backups -name com.googlecode.iterm2.plist)" ]'
check "terminal: the guid written matches the profile file" \
  'grep -q "\"Guid\": \"mise-me-profile\"" "$core/assets/iterm2-profile.json"'

fresh_home tirun
mkdir -p "$H/.fake-defaults"; echo x > "$H/.fake-defaults/New Bookmarks"
term MISE_ME_TERMINALS=iterm2 MISE_ME_APP_DIRS="$apps/with" FAKE_RUNNING=iTerm2; rc=$?
check "terminal: a running iTerm2 is not written to; Set as Default becomes a next step" \
  '[ "$rc" -eq 0 ] && [ ! -e "$H/.fake-defaults/Default Bookmark Guid" ] && steps | grep -q "Set as Default"'

# --- Ghostty: one config file, no profiles ---
fresh_home tgnone
term MISE_ME_TERMINALS=ghostty; rc=$?
check "terminal: ghostty without Ghostty installed writes the config and adds an install step" \
  '[ "$rc" -eq 0 ] && cmp -s "$core/assets/ghostty-config" "$H/$gconfig" && steps | grep -q "Install Ghostty" && [ ! -d "$H/Applications" ]'
check "terminal: the ghostty choice is saved" '[ "$(saved)" = ghostty ]'

fresh_home tgdecline
term MISE_ME_TERMINALS=ghostty MISE_ME_INSTALL_APPS=no; rc=$?
check "terminal: declining the download still writes the config and leaves the install step" \
  '[ "$rc" -eq 0 ] && [ -f "$H/$gconfig" ] && steps | grep -q "Install Ghostty"'

fresh_home tgaccept
term MISE_ME_TERMINALS=ghostty MISE_ME_INSTALL_APPS=yes CURL_FAIL=1; rc=$?
check "terminal: accepting the download fetches Ghostty first, and a failed download stops setup" \
  '[ "$rc" -ne 0 ] && [ ! -d "$H/Applications" ] && [ ! -e "$H/$gconfig" ]'

fresh_home tginstall
term MISE_ME_TERMINALS=ghostty MISE_ME_INSTALL_APPS=yes FAKE_CURL_DIR="$dl" FAKE_SHA="$ghostty_sha" MISE_ME_APP_DIRS="$work/apps-tginstall"; rc=$?
check "terminal: accepting the download installs Ghostty, writes the config and exits 0" \
  '[ "$rc" -eq 0 ] && [ -d "$work/apps-tginstall/Ghostty.app" ] && cmp -s "$core/assets/ghostty-config" "$H/$gconfig" && [ -z "$(steps)" ] && grep -q "installed .*Ghostty.app" "$H/.out"'
dmg=$(sed -n 's/^attach .* //p' "$H/.hdiutil.log")
check "terminal: the disk image is detached once, and the download folder is removed" \
  '[ "$(grep -c "^detach" "$H/.hdiutil.log")" -eq 1 ] && [ -n "$dmg" ] && [ ! -e "$(dirname "$dmg")" ]'
rm -rf "$work/apps-tginstall"

fresh_home tgbadsum
term MISE_ME_TERMINALS=ghostty MISE_ME_INSTALL_APPS=yes FAKE_CURL_DIR="$dl" MISE_ME_APP_DIRS="$work/apps-tgbadsum"; rc=$?
check "terminal: a download with the wrong checksum is not installed" \
  '[ "$rc" -ne 0 ] && [ ! -d "$work/apps-tgbadsum" ] && grep -q "checksum mismatch" "$H/.out"'

fresh_home tiinstall
term MISE_ME_TERMINALS=iterm2 MISE_ME_INSTALL_APPS=yes FAKE_CURL_DIR="$dl" FAKE_SHA="$iterm_sha" MISE_ME_APP_DIRS="$work/apps-tiinstall"; rc=$?
check "terminal: accepting the download installs iTerm2 and asks to set the default after its first launch" \
  '[ "$rc" -eq 0 ] && [ -d "$work/apps-tiinstall/iTerm.app" ] && [ -f "$H/$iprofile" ] && steps | grep -q "Open iTerm2, then"'
rm -rf "$work/apps-tiinstall"

fresh_home tgclosed
term MISE_ME_TERMINALS=ghostty MISE_ME_APP_DIRS="$apps/with"; rc=$?
check "terminal: an installed, closed Ghostty gets the config with no next step" \
  '[ "$rc" -eq 0 ] && cmp -s "$core/assets/ghostty-config" "$H/$gconfig" && [ -z "$(steps)" ] && [ -z "$(ascalls)" ]'
printf 'mine\n' > "$H/$gconfig"
term MISE_ME_TERMINALS=ghostty MISE_ME_APP_DIRS="$apps/with"; rc=$?
check "terminal: a changed Ghostty config is backed up before it is replaced" \
  '[ "$rc" -eq 0 ] && cmp -s "$core/assets/ghostty-config" "$H/$gconfig" && [ -n "$(backups -type f -name config)" ]'

fresh_home tgrun
term MISE_ME_TERMINALS=ghostty MISE_ME_APP_DIRS="$apps/with" FAKE_RUNNING=ghostty; rc=$?
check "terminal: a running Ghostty gets the config and a reload step" \
  '[ "$rc" -eq 0 ] && [ -f "$H/$gconfig" ] && steps | grep -q "reload"'
rm -f "$H/.local/state/mise-me/next-steps"   # setup, not this task, starts the list afresh
term MISE_ME_TERMINALS=ghostty MISE_ME_APP_DIRS="$apps/with" FAKE_RUNNING=ghostty; rc=$?
check "terminal: an already set up Ghostty is left alone, even while running" \
  '[ "$rc" -eq 0 ] && [ -z "$(steps)" ] && [ -z "$(backups -type f)" ]'

fresh_home tall
term MISE_ME_TERMINALS=all MISE_ME_APP_DIRS="$apps/with"; rc=$?
check "terminal: --terminal all sets up the three apps" \
  '[ "$rc" -eq 0 ] && [ "$(saved)" = ghostty,iterm2,terminal-app ] && [ -f "$H/$gconfig" ] && [ -f "$H/$iprofile" ] && ascalls | grep -q " apply "'

fresh_home ttclosed
term MISE_ME_TERMINALS=terminal-app; rc=$?
check "terminal: a closed Terminal.app gets the mise-me profile written directly" \
  '[ "$rc" -eq 0 ] && ascalls | grep -q " apply .* JetBrainsMonoNF-Regular" && [ -z "$(opened)" ] && [ -z "$(steps)" ]'
check "terminal: Terminal.app's settings are backed up before they are changed" \
  '[ -n "$(backups -name com.apple.Terminal.plist)" ]'

fresh_home ttrun
term MISE_ME_TERMINALS=terminal-app FAKE_RUNNING=Terminal FAKE_TA_STATUS="Pro	missing"; rc=$?
check "terminal: a running Terminal.app imports the profile file and makes it the default" \
  '[ "$rc" -eq 0 ] && ! ascalls | grep -q " apply " && ascalls | grep -q " export .*mise-me.terminal" && opened | grep -q "mise-me.terminal$" && ascalls | grep -q "set default settings to settings set \"mise-me\"" && [ -z "$(steps)" ]'

fresh_home ttrundef
term MISE_ME_TERMINALS=terminal-app FAKE_RUNNING=Terminal FAKE_TA_STATUS="Pro	current"; rc=$?
check "terminal: a running Terminal.app with the profile only gets it set as the default" \
  '[ "$rc" -eq 0 ] && [ -z "$(opened)" ] && ascalls | grep -q "set default settings" && [ -z "$(steps)" ]'

fresh_home ttrunold
term MISE_ME_TERMINALS=terminal-app FAKE_RUNNING=Terminal FAKE_TA_STATUS="mise-me	outdated"; rc=$?
check "terminal: an outdated profile in a running Terminal.app becomes a next step, not a second copy" \
  '[ "$rc" -eq 0 ] && [ -z "$(opened)" ] && ! ascalls | grep -q " apply \| export \|set default" && steps | grep -q "update the mise-me profile"'

fresh_home ttdone
term MISE_ME_TERMINALS=terminal-app FAKE_TA_STATUS="mise-me	current"; rc=$?
check "terminal: an already set up Terminal.app is left alone" \
  '[ "$rc" -eq 0 ] && ! ascalls | grep -q " apply " && [ -z "$(steps)" ] && [ -z "$(backups -type f)" ]'

fresh_home tsaved
term MISE_ME_TERMINALS=none
: > "$H/.osascript.log"
term TERM_PROGRAM=Apple_Terminal; rc=$?
check "terminal: a re-run uses the saved choice instead of detecting" \
  '[ "$rc" -eq 0 ] && [ "$(saved)" = none ] && [ -z "$(ascalls)" ] && [ ! -e "$H/$iprofile" ]'
term MISE_ME_TERMINALS=both; rc=$?
check "terminal: --terminal replaces the saved choice" '[ "$rc" -eq 0 ] && [ "$(saved)" = iterm2,terminal-app ]'

fresh_home tbad
term MISE_ME_TERMINALS=konsole; rc=$?
check "terminal: an unknown app stops with an error and changes nothing" \
  '[ "$rc" -ne 0 ] && [ -z "$(saved)" ] && [ -z "$(ascalls)" ]'

fresh_home tlinux
printf '#!/bin/sh\necho Linux\n' > "$work/linux-uname"; mkdir -p "$work/lstub"; cp "$work/linux-uname" "$work/lstub/uname"; chmod +x "$work/lstub/uname"
env -i HOME="$H" PATH="$work/lstub:$stub:/usr/bin:/bin" MISE_ME_TERMINALS=iterm2 sh "$core/mise-tasks/terminal" </dev/null >/dev/null 2>&1; rc=$?
check "terminal: does nothing outside macOS" '[ "$rc" -eq 0 ] && [ -z "$(ls -A "$H")" ]'

check "terminal: nothing machine-specific is hardcoded (no user paths or profile names)" \
  '! grep -nE "/Users/|/home/[a-z]|Clear Dark" "$core/mise-tasks/terminal" "$core/assets/terminal-app.js" "$core/assets/ghostty-config" "$core/assets/iterm2-profile.json"'
check "terminal: the three apps share one set of colours" \
  'for h in 212734 e6e6e6 f0f0f0 334e5e 5a524c ea6962 a9b665 d8a657 7daea3 d3869b 89b482 dee5eb e5eff5; do grep -qi "$h" "$core/assets/ghostty-config" && grep -qi "$h" "$core/assets/terminal-app.js" || exit 1; done'

# The real Terminal.app helper, against a throwaway settings domain (macOS).
if [ "$(uname -s)" = Darwin ] && command -v osascript >/dev/null 2>&1 &&
  osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSFont.fontWithNameSize("Menlo-Regular", 12).isNil() ? 1 : 0' >/dev/null 2>&1; then
  dom="mise-me.test.$$"
  ta="$core/assets/terminal-app.js"
  defaults write "$dom" "Default Window Settings" -string Pro
  s1=$(osascript -l JavaScript "$ta" status "$dom" Menlo-Regular 2>&1)
  osascript -l JavaScript "$ta" apply "$dom" Menlo-Regular >/dev/null 2>&1; rc=$?
  s2=$(osascript -l JavaScript "$ta" status "$dom" Menlo-Regular 2>&1)
  s3=$(osascript -l JavaScript "$ta" status "$dom" Courier 2>&1)
  startup=$(defaults read "$dom" "Startup Window Settings" 2>/dev/null)
  others=$(defaults read "$dom" "Window Settings" 2>/dev/null | grep -c '"Pro"\|Pro =')
  osascript -l JavaScript "$ta" export "$work/mise-me.terminal" Menlo-Regular >/dev/null 2>&1
  defaults delete "$dom" >/dev/null 2>&1
  rm -f "$HOME/Library/Preferences/$dom.plist"
  check "terminal-app.js: a missing mise-me profile is reported along with the current default" \
    '[ "$s1" = "Pro	missing" ]'
  check "terminal-app.js: apply adds the profile and makes it the default, leaving other profiles alone" \
    '[ "$rc" -eq 0 ] && [ "$s2" = "mise-me	current" ] && [ "$startup" = mise-me ] && [ "$others" -eq 0 ]'
  check "terminal-app.js: a profile that differs from the file is reported as outdated" \
    '[ "$s3" = "mise-me	outdated" ]'
  check "terminal-app.js: export writes a profile file Terminal.app can import" \
    'plutil -lint "$work/mise-me.terminal" >/dev/null && [ "$(plutil -extract name raw "$work/mise-me.terminal")" = mise-me ]'
fi
