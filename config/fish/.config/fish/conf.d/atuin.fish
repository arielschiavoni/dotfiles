#
# atuin has a fish related issue. Need to temporarily work around it.
# https://github.com/atuinsh/atuin/issues/2803, https://github.com/atuinsh/atuin/issues/2940
# atuin init fish | source
atuin init fish | sed "s/-k up/up/g" | source
# atuin init fish | source
