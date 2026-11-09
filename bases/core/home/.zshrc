# zsh config managed by mise-me. Put anything personal in ~/.zshrc.local.

export PATH="$HOME/.local/bin:$PATH"

# History
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space

# Completion (dump goes under XDG cache so no hostname-named file lands in $HOME)
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# Word movement with Option/Alt (or Ctrl) + arrows. zsh binds ESC b / ESC f
# but not the codes terminals send for modified arrows:
#   ^[[1;3D / ^[[1;3C  Terminal.app, most Linux terminals (Option/Alt)
#   ^[^[[D / ^[^[[C    iTerm2 with Option sending Esc+
#   ^[[1;5D / ^[[1;5C  Ctrl + arrows
bindkey '^[[1;3D' backward-word '^[[1;3C' forward-word
bindkey '^[^[[D' backward-word '^[^[[C' forward-word
bindkey '^[[1;5D' backward-word '^[[1;5C' forward-word

# Tools installed by mise
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# fzf key bindings: Ctrl+T file paths, Option/Alt+C cd, and ** + Tab
# completion (Ctrl+R too, until atuin takes it over below). Before syntax
# highlighting, which must wrap them.
if command -v fd >/dev/null 2>&1; then
  # fd finds files for fzf: faster than find, follows .gitignore, shows dotfiles
  export FZF_DEFAULT_COMMAND="${FZF_DEFAULT_COMMAND:-fd --type f --hidden --follow --exclude .git}"
  export FZF_CTRL_T_COMMAND="${FZF_CTRL_T_COMMAND:-$FZF_DEFAULT_COMMAND}"
  export FZF_ALT_C_COMMAND="${FZF_ALT_C_COMMAND:-fd --type d --hidden --follow --exclude .git}"
fi
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)

# atuin: Ctrl+R searches a history database (this folder, this session, ...).
# The Up arrow stays plain zsh history, so autosuggestions keep working.
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh --disable-up-arrow)"

# Plugins downloaded by `mise run zsh-plugins`
_zsh_plugins="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
# fzf-tab: Tab completion in an fzf menu, with a folder preview for cd.
# After compinit and before the other plugins, which wrap its widgets.
if [ -r "$_zsh_plugins/fzf-tab/fzf-tab.plugin.zsh" ]; then
  zstyle ':completion:*' menu no
  zstyle ':completion:*:descriptions' format '[%d]'
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS:-di=34:ln=36:ex=32}"
  zstyle ':fzf-tab:complete:(cd|z|zi|ls|ll|eza):*' fzf-preview 'eza -1 --color=always --icons=auto $realpath 2>/dev/null'
  zstyle ':fzf-tab:*' switch-group '<' '>'
  source "$_zsh_plugins/fzf-tab/fzf-tab.plugin.zsh"
fi
[ -r "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] &&
  source "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
# syntax highlighting must load last among plugins
[ -r "$_zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] &&
  source "$_zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _zsh_plugins

# Aliases
if command -v eza >/dev/null 2>&1; then
  # eza's default colours, minus bold (directories, executables, permissions,
  # user). Set EZA_COLORS in ~/.zshrc.local to override.
  export EZA_COLORS="${EZA_COLORS:-di=34:ex=32:ur=33:uw=31:ux=32:ue=32:gr=33:gw=31:gx=32:tr=33:tw=31:tx=32:su=35:sf=35:xa=37:xx=90:uu=33:gu=33:lp=36}"
  # --icons=auto, not bare --icons: eza would read the next argument
  # (`ls some/dir`) as the value of --icons and fail.
  alias ls="eza --icons=auto"
  alias ll="eza --icons=auto -lah"
fi
command -v bat >/dev/null 2>&1 && alias cat="bat"

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Extensions drop their shell snippets here
for _f in "${XDG_CONFIG_HOME:-$HOME/.config}"/zsh/conf.d/*.zsh(N); do
  source "$_f"
done
unset _f

# Machine-local additions (never part of mise-me)
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
