# dotfiles


## Create symlinks with stow

```sh
$ stow --target ~/Library/ApplicationSupport/Spectacle/ spectacle
$ stow --target ~/Library/ApplicationSupport/Code/User/ vscode
$ stow --target ~ git tig fish nvim
```

NB!: stow will complain if the files it is trying to link already exist, so they need to be removed first.

## Resources Stow vs Nix (home-manager)
- https://alexpearce.me/2016/02/managing-dotfiles-with-stow/
- https://alexpearce.me/2021/07/managing-dotfiles-with-nix/
- https://www.youtube.com/playlist?list=PLRGI9KQ3_HP_OFRG6R-p4iFgMSK1t5BHs


