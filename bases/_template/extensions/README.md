Extensions that only this base can use go here, one folder each:

    extensions/<name>/ext.toml      description = "..."
    extensions/<name>/home/...      files to add, mirroring $HOME

An extension only adds files. Put tools in home/.config/mise/conf.d/<name>.toml
and shell snippets in home/.config/zsh/conf.d/<name>.zsh. Never ship a file
the base already owns (such as .zshrc or .config/mise/config.toml).
