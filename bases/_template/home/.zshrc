# zsh config for this base. Put anything personal in ~/.zshrc.local.

export PATH="$HOME/.local/bin:$PATH"

autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# Extensions drop their shell snippets here (keep this loop in every base)
for _f in "${XDG_CONFIG_HOME:-$HOME/.config}"/zsh/conf.d/*.zsh(N); do
  source "$_f"
done
unset _f

[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
