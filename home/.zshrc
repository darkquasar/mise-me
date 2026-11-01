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

# Tools installed by mise
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# Plugins cloned by `mise run zsh-plugins`
_zsh_plugins="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
[ -r "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] &&
  source "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
# syntax highlighting must load last among plugins
[ -r "$_zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] &&
  source "$_zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _zsh_plugins

# Aliases
if command -v eza >/dev/null 2>&1; then
  alias ls="eza --icons"
  alias ll="eza --icons -lah"
fi
command -v bat >/dev/null 2>&1 && alias cat="bat"

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Machine-local additions (never part of mise-me)
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
