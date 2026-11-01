# mise-me

A portable terminal environment built with [mise](https://mise.jdx.dev). It sets up
zsh, a starship prompt, herdr, Docker Sandboxes (sbx), patronus, the claude and codex
CLIs and a set of everyday command-line tools. It carries no personal identity: no
git name or email, no credentials, no hostnames and no machine paths.

## Use it

Runs on macOS on Apple silicon and on Linux (x86_64 or arm64). Needs `bash`, `curl`,
`tar` and `zsh` already installed (macOS has all four; on Ubuntu run
`sudo apt install zsh`). `setup` checks these first and stops before changing
anything if one is missing.

```sh
git clone <this repo> mise-me
cd mise-me
./bin/mise run setup
exec zsh
```

`./bin/mise` is a bash script committed to the repo (generated with
`mise generate install-script`). It downloads a pinned mise release from GitHub,
verifies its checksum, and runs it. So nothing has to be installed first.

If you prefer the official installer, this works too:

```sh
curl -fsSL https://mise.run | sh
~/.local/bin/mise run setup
```

## What `setup` does

```
  setup
    |-- self         copy mise to ~/.local/bin/mise
    |-- dotfiles     copy home/* into $HOME (existing files are backed up first)
    |-- tools        mise install: every tool in ~/.config/mise/config.toml
    |-- prompt       write the stock starship gruvbox-rainbow preset
    |-- zsh-plugins  zsh-autosuggestions + zsh-syntax-highlighting (pinned tarballs)
    '-- terminal     macOS only: JetBrainsMono Nerd Font + iTerm2 "mise-me" profile
```

Each step is its own task (`mise tasks ls`), and each one is safe to run again.
Nothing is overwritten: any file or folder that would be replaced is moved to
`~/.local/state/mise-me/backups/` first. Config files follow `XDG_CONFIG_HOME` (and
`MISE_CONFIG_DIR` for mise); the starship config follows `STARSHIP_CONFIG`. The zsh
plugins and the font are pinned and checked against a SHA-256 before use.

Run the offline regression tests with `sh tests/run.sh`.

| Group | Tools |
| --- | --- |
| Shell and prompt | starship, eza, bat, zoxide, fzf, ripgrep, jq, gh |
| Languages | node 22, go, rust, uv, pixi, deno |
| Agents | claude, codex |
| Workspace | herdr, sbx, patronus |

Change versions in `home/.config/mise/config.toml`, then run `mise run dotfiles` and `mise run tools`.

## Left to each machine

These are deliberately not automated, because they are personal:

- `git config --global user.name` and `user.email`
- `sbx login`
- signing in to claude and codex
- in iTerm2, setting the `mise-me` profile as default
- anything else you want in your shell: put it in `~/.zshrc.local`, which mise-me never touches

## Notes

- patronus is installed from `github.com/darkquasar/patronus`, so that repository
  name appears in the mise config.
- On Linux, `sbx` also needs KVM and the setup steps in Docker's
  [install guide](https://docs.docker.com/ai/sandboxes/install/); mise only puts the
  binary on your `PATH`.
- When you test inside an sbx sandbox, sbx copies your host git identity into the
  sandbox's `~/.gitconfig`. That comes from sbx, not from this repo.
