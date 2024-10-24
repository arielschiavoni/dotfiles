# dotfiles

## Create symlinks with stow

```sh
$ cd ~/code/personal/dotfiles
$ stow --target ~/Library/ApplicationSupport/Code/User/ vscode
$ stow --target ~ git tig fish nvim tmux alacritty
```

NB!: stow will complain if the files it is trying to link already exist, so they need to be removed first.

## GPG key

- Follow [this](https://risanb.com/code/backup-restore-gpg-key/) guide to backup/restore GPG keys

## Resources Stow vs Nix (home-manager)

- https://alexpearce.me/2016/02/managing-dotfiles-with-stow/
- https://alexpearce.me/2021/07/managing-dotfiles-with-nix/
- https://www.youtube.com/playlist?list=PLRGI9KQ3_HP_OFRG6R-p4iFgMSK1t5BHs
