{
  description = "Ariel's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager }:
  let
    # this is the darwin configuration
    # man 5 configuration.nix
    # https://mynixos.com/nix-darwin/options
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = [ ];

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
      nixpkgs.config.allowUnfree = true;

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

      users.users."ariel.schiavoni".home = "/Users/ariel.schiavoni";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#macbook
    darwinConfigurations."macbook" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        home-manager.darwinModules.home-manager
        {
          # https://nix-community.github.io/home-manager/nix-darwin-options.xhtml
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.verbose = true;
          home-manager.users."ariel.schiavoni" = import ./home.nix;
        }
      ];
    };
  };
}
