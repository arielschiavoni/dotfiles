# Installation guide EndeavourOS

1. Clone dotfiles

```bash
mkdir -p ~/code/personal
cd ~/code/personal
git clone https://github.com/arielschiavoni/dotfiles.git
```

2. Install all packages

```bash
./linux/install.sh
```

3. Link configuration using stow

```bash
./linux/config.sh
```

4. Manually install gnome extensions using "Gnome Extension Manager"

5. Load Gnome extensions config

```bash
$ dconf load /org/gnome/shell/extensions/ < config/gnome-extensions.conf
```

## Persist Gnome Extensions config

```bash
$ dconf dump /org/gnome/shell/extensions/ > config/gnome-extensions.conf
```

## 1Password CLI

The 1Password CLI is useful to give NeoVim access to read passwords for Gemini or ChatGPT plugins.
The package is only available in AUR repository with `yay`. To be 100% sure the package is not tempered this tool is manually
installed following the official [guide](https://developer.1password.com/docs/cli/get-started/).
