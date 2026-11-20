# Rex

`config/rex/.config/rex/init.lua` is stowed to `~/.config/rex/init.lua`
on the Mac. It declares `devbox` at `ssh://devbox-rex`.
`devbox/scripts/ssh-config.sh` generates the SSH alias for Rex alongside the
interactive `devbox` alias. Rex opens its own SSH connection and reaches the
guest’s personal server, started on demand by the `rex.socket` user unit.

## Client setup

Rex reads `init.lua` in the server process. The host declaration is loaded
by the Mac’s local server; it does not configure the Mac app’s initial
connection or local-server startup.

In the Mac app, use **Add Remote Host…** and enter `ssh://devbox-rex`.
Replace any saved entry that points to `~/.ssh/rex-devbox.sock`. The app stores
this connection separately from the Lua file. You can connect directly from
the CLI with `rex -S ssh://devbox-rex ls`.

This package is kept out of the devbox’s stow list: its host endpoint uses the
Mac’s SSH alias. Put server-side keybindings and custom actions in the devbox’s
own Rex config for remote sessions.

Rex loads its Lua config when the server starts. After editing a running
server’s config, **Reload Config** or `rex config reload` applies it.

References: [Configuration file](https://www.superlogical.com/rex/docs/customize/config),
[Lua host declarations](https://www.superlogical.com/rex/docs/reference/lua#hosts-and-other-servers),
[SSH remote access](https://www.superlogical.com/rex/docs/linux/remote-access#ssh).
