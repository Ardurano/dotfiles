# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.
- This is a public repo and `home/` is symlinked into a real home directory. Never move a secret into it - not `~/.zshrc` with inline AWS keys, not `~/.config/cms-secrets.env`, not credential files of any kind.
- `MIGRATION.md` explains why `configuration.nix` declares ~30 Homebrew formulae that arguably belong in nixpkgs, and why `programs.zsh.enable` is `false`. Both are staged migration state, not oversights. Read it before "fixing" either.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
