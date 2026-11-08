# Rex

`config/rex/.config/rex/init.lua` is stowed to `~/.config/rex/init.lua`
on the Mac. It declares the `devbox` host using the Unix socket forwarded
by the `Host devbox` block in `~/.ssh/config`.

`devbox/scripts/ssh-config.sh` queries the guest UID to generate the remote
socket path. An SSH connection keeps the forward available. The guest’s
`rex.socket` user unit starts the personal server when a client connects.

## Client setup

Rex reads `init.lua` in the server process. The host declaration is loaded
by the Mac’s local server; it does not configure the Mac app’s initial
connection or local-server startup.

With the local server blocked, use **Add Remote Host…** in the Mac app and
enter `/Users/ariel.schiavoni/.ssh/rex-devbox.sock`. That initial connection
is stored by the app separately from this Lua file.

This package is kept out of the devbox’s explicit stow list: its host
endpoint uses the Mac’s SSH forward. Add server-side keybindings and
custom actions to a config on the devbox when using remote sessions.

Rex loads its Lua config when the server starts. After editing a running
server’s config, **Reload Config** or `rex config reload` applies it.

References: [Configuration file](https://www.superlogical.com/rex/docs/customize/config),
[Lua host declarations](https://www.superlogical.com/rex/docs/reference/lua#hosts-and-other-servers),
[SSH forwarding](https://www.superlogical.com/rex/docs/linux/remote-access#ssh-forwarding).
