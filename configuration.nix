{ user, inputs, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  # `pkgs.unstable.<name>` pulls from nixpkgs-unstable. Derive the platform from
  # hostPlatform above so there is still only one place to change it for Intel.
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })
  ];

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    # This machine already had a hand-installed Homebrew at /opt/homebrew before
    # nix-homebrew existed. Without autoMigrate, activation aborts rather than
    # adopt a prefix it doesn't own.
    autoMigrate = true;
  };

  # Ownership split, deliberate: Homebrew owns GUI casks and the handful of CLI
  # tools nixpkgs can't serve; everything else is a Nix package in home.nix. No
  # tool is installed twice, so nothing is ambiguous on PATH.
  #   - ghostty      - nixpkgs sets platforms = linux, no darwin build exists
  #   - wezterm      - cask ships /Applications/WezTerm.app so Spotlight finds it
  #   - herdr        - not in nixpkgs
  #   - copilot-cli  - not in nixpkgs
  #   - opensuperwhisper - third-party tap only
  #   - ollama       - runs as a brew-managed LaunchAgent; the Nix package would
  #                    install fine but nothing would recreate the auto-start
  #   - pyenv        - nixpkgs is pinned at 2.6.31 on both channels vs 2.8.4 here,
  #                    and the version determines which Pythons python-build can
  #                    compile. A Nix copy can't self-update.
  #   - gettext      - pyenv-built Pythons (e.g. 3.12.12) dynamically link against
  #                    /opt/homebrew/opt/gettext/lib/libintl.8.dylib at build time.
  #                    A Nix-store gettext wouldn't land at that path, so the brew
  #                    keg must exist or those interpreters fail to start; without
  #                    this entry `cleanup = "zap"` removes it as unlisted.
  #   - jenv         - not in nixpkgs on either channel
  #   - corretto@21  - pkgs.corretto21/corretto25 set meta.platforms to Linux
  #     corretto@25    only, so nixpkgs cannot serve a Corretto JDK on darwin at
  #                    all. The casks also drop their .pkg into
  #                    /Library/Java/JavaVirtualMachines, which is where
  #                    /usr/libexec/java_home, IntelliJ and the rest of the team
  #                    look for a JDK. Both are pinned to a major version rather
  #                    than the unversioned `corretto` cask, which would drift to
  #                    26 on release and silently change what `jenv` resolves.
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      "my-monkeys/tap"  # opensuperwhisper
    ];
    brews = [
      "gettext"
      "herdr"
      "jenv"
      { name = "ollama"; restart_service = "changed"; }
      "pyenv"
    ];
    casks = [
      "copilot-cli"
      "corretto@21"
      "corretto@25"
      "ghostty"
      "my-monkeys/tap/opensuperwhisper"
      "wezterm"
      "raycast"
    ];
  };
}
