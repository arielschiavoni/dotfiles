# Static equivalent of `brew shellenv fish`.
#
# brew shellenv emits six constant lines pointing at /opt/homebrew, but costs
# 131-161ms to do it (17% CPU - it is I/O bound, not computing anything).
# Hardcoding the output is byte-identical and free.
if test -d /opt/homebrew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    set -gx HOMEBREW_CELLAR /opt/homebrew/Cellar
    set -gx HOMEBREW_REPOSITORY /opt/homebrew
    fish_add_path --global --move --path /opt/homebrew/bin /opt/homebrew/sbin
    if test -n "$MANPATH[1]"
        set -gx MANPATH '' $MANPATH
    end
    if not contains /opt/homebrew/share/info $INFOPATH
        set -gx INFOPATH /opt/homebrew/share/info $INFOPATH
    end
end
