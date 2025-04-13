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
