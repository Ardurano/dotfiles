{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # A few tools move faster than a stable release branch backports. 26.05 only
    # takes security fixes, so glow/uv/gemini-cli/neovim would sit a release
    # behind until 26.11. configuration.nix exposes this as `pkgs.unstable`.
    # Still fully pinned - flake.lock locks this rev too.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    antigravity.url = "github:Hy4ri/antigravity-flake";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-unstable, antigravity }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your macOS username differs.
      user = "arnej";
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user inputs; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Rename anything already sitting where Home Manager wants to write
            # instead of aborting the switch. Turns a failed activation into a
            # recoverable ~/.config/foo.hm-bak.
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = { inherit user inputs; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
