{ config, lib, pkgs, user, inputs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  # Nix owns CLI tools; Homebrew owns GUI casks plus the few tools nixpkgs can't
  # serve (see configuration.nix). Nothing appears on both sides.
  home.packages = with pkgs; [
    # search and navigation
    fd        # fast find
    fzf       # fuzzy finder
    ripgrep   # fast search
    tree
    wget
    # git
    git
    gh
    lazygit
    # containers - colima supplies the engine, so only the client is needed
    colima
    docker-client
    docker-buildx
    docker-compose
    docker-credential-helpers
    # languages and build tools
    go
    maven
    kotlin
    gradle
    ktlint
    # The rustup proxies only; toolchains stay mutable in ~/.rustup, so
    # per-project rust-toolchain.toml and `rustup override` keep working.
    # Pinning rustc/cargo from nixpkgs instead would give up both.
    rustup
    lua5_4
    luarocks
    tree-sitter
    pipenv
    nodejs
    # text and data
    jq        # json on the command line
    pandoc
    chroma    # syntax highlighter behind oh-my-zsh's colorize plugin
    hl-log-viewer  # the `hl` log viewer the gateway_run alias pipes into
    # gnu userland - these shadow the BSD versions macOS ships
    coreutils
    findutils
    # crypto - gpg-agent needs a graphical pinentry on macOS
    gnupg
    pinentry_mac
    # Fonts. Hack is what wezterm.lua asks for; JetBrainsMono is what the Ghostty
    # config asks for and was previously a hand-dropped ~/Library/Fonts install,
    # which would not have survived a move to a new machine.
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
    aider-chat
    inputs.antigravity.packages.${pkgs.system}.antigravity-cli
    # System
    btop
    # AI
    rtk
  ]
  # Tools where the 26.05 release branch sits far enough behind to matter.
  # See the nixpkgs-unstable input in flake.nix.
  ++ (with pkgs.unstable; [
    glow        # 26.05 has 2.1.2, a major version behind
    uv          # uv ships constantly; 26.05 is 0.11.x
    neovim      # 0.12.x is required - init.lua uses vim.pack
  ]);
  fonts.fontconfig.enable = true;
  # nix-darwin's set-environment exports EDITOR=nano system-wide; override it.
  # programs.zsh.initContent narrows this to vim over ssh.
  home.sessionVariables.EDITOR = "nvim";
  # The native Claude installer lives here. Prepended by the old ~/.zshrc.
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Home Manager owns ~/.zshrc, ~/.zshenv and ~/.zprofile. Anything secret or
  # employer-specific lives in an untracked ~/.zshrc.local, sourced at the end -
  # this repo is public.
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid

    # /etc/zshrc caps history at 2000 lines, which is small enough to lose
    # things worth recalling.
    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;   # a leading space keeps a command out of history
      extended = true;      # record timestamps
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "vi-mode"
        "history-substring-search"
        "fzf"
        "colorize"  # needs chroma, in home.packages
        "aws"
      ];
    };

    localVariables.COMPLETION_WAITING_DOTS = "true";

    sessionVariables = {
      LANG = "en_US.UTF-8";
      FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    };

    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "caffeinate -dimsu claude --model sonnet";
      co = "codex --full-auto";
      vim = "nvim";
      vi = "nvim";
      git-branch = "git rev-parse --abbrev-ref HEAD | pbcopy";
    };

    # Login shells need Homebrew on PATH for the three tools it still owns.
    # nix-darwin's /etc/zshrc does this too, but only for interactive shells.
    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    initContent = lib.mkMerge [
      ''
      bindkey '^f' autosuggest-accept

      # Must be evaluated per shell - gpg needs the current terminal to prompt on.
      export GPG_TTY=$(tty)

      # nvim everywhere except over ssh, where the remote may not have it.
      if [[ -n $SSH_CONNECTION ]]; then
        export EDITOR='vim'
      else
        export EDITOR='nvim'
      fi

      # jenv owns the java/javac shims so Corretto 21 and 25 can coexist and be
      # switched per project with a .java-version file. The JDKs themselves are
      # declared casks; what lives in ~/.jenv stays mutable state, the same call
      # this repo already makes for ~/.pyenv/versions and ~/.rustup/toolchains.
      # `jenv add` records a JDK - README lists the commands for a fresh machine.
      # This has to be evaluated before pyenv below so pyenv's shims remain the
      # last thing prepended to PATH; the two shim no commands in common.
      command -v jenv >/dev/null && eval "$(jenv init -)"

      # pyenv stays on Homebrew - see MIGRATION.md. Its shims have to be
      # prepended last so they win for python and pip.
      export PYENV_ROOT="$HOME/.pyenv"
      [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
      eval "$(pyenv init - zsh)"

      # rustup comes from Nix, so ~/.cargo/bin holds only whatever
      # `cargo install` puts there. Append rather than prepend, so those
      # binaries stay reachable but can never shadow a declared package -
      # a cargo-installed tree-sitter shadowing the Nix one is exactly how
      # this bit once. home.sessionPath prepends, hence doing it here.
      path+=("$HOME/.cargo/bin")
      ''

      # mkAfter (order 1500) puts this past shellAliases (1100) and
      # zsh-syntax-highlighting (1200), so ~/.zshrc.local can genuinely
      # override anything this repo declares.
      (lib.mkAfter ''
        # Machine-local overrides, employer-specific aliases, and secrets.
        # Never tracked; this repo is public.
        [ -f ~/.zshrc.local ] && source ~/.zshrc.local
      '')
    ];
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".config/ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/statusline.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline.sh";
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline-command.sh";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".gemini/antigravity-cli/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.gemini/antigravity-cli/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
