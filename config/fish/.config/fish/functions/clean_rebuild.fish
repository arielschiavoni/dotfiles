function clean_rebuild -d "Delete node_modules/.wireit/dist, reinstall, and rebuild (optionally one workspace)"
    # Usage:
    #   clean_rebuild                            # build everything
    #   clean_rebuild packages/renderer-api      # build a single workspace
    #
    # --prune stops fd descending once it has matched a directory, so nested
    # node_modules inside a match are not traversed.
    # xargs --max-procs 0 parallelises the deletions; --verbose echoes each one.

    set -l workspace $argv[1]

    fd --no-ignore --hidden --type d node_modules --prune . \
        | xargs --verbose --max-procs 0 -I DIR rm -rf DIR
    fd --no-ignore --hidden --type d '(.wireit|dist)' --prune . \
        | xargs --verbose --max-procs 0 -I DIR rm -rf DIR

    npm ci
    or return 1

    if test -n "$workspace"
        npm run build --workspace=$workspace
    else
        npm run build
    end
end
