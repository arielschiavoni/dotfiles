# Nix

## Pre-requisites

1. Install `nix` using the [Determinate nix-installer](https://github.com/DeterminateSystems/nix-installer)
2. Install [nix-darwin](https://github.com/LnL7/nix-darwin)

## Update packages

```bash
nix flake update --flake ~/code/personal/dotfiles/nix-darwin#macbook
darwin-rebuild switch --flake ~/code/personal/dotfiles/nix-darwin#macbook
```

## Examples

- https://github.com/dustinlyons/nixos-config
