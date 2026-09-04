function fish_reload -d "Clear caches and fully reload fish configuration"
    # gopass secrets are cached so GPG prompts once per machine, not per shell.
    # Drop it so the next startup re-reads from gopass.
    rm -f ~/.cache/gopass/shell-env
    for f in ~/.cache/gopass/github-token-*
        rm -f -- $f
    end

    # exec replaces this process, so every conf.d/*.fish and config.fish is
    # re-read from scratch. Re-sourcing them in place would double-apply
    # abbreviations, PATH entries and prompt hooks.
    #
    # CAVEAT: exec inherits the exported environment, so this picks up added and
    # changed `set -gx` values but NOT deletions - remove a `set -gx` line and
    # the old value is still inherited. Use `set -e VAR`, or open a new pane.
    # Universal variables (fish_variables on disk) are likewise unaffected.
    exec fish
end
