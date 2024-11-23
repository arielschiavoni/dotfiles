{
  description = "My nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = 
        [
          pkgs.neofetch 
          pkgs.alacritty 
        ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

      # man 5 configuration.nix
      # https://mynixos.com/nix-darwin/options
      system.defaults = {
        dock.autohide = true;
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          # 120, 90, 60, 30, 12, 6, 2
          KeyRepeat = 2;
          # 120, 94, 68, 35, 25, 15
          InitialKeyRepeat = 15;
          AppleShowAllExtensions = true;
        };
        finder.FXPreferredViewStyle = "Nlsv";
      };

    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#macbook
    darwinConfigurations."macbook" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
