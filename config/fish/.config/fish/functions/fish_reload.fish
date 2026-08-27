function fish_reload -d "Clear gopass and fish bundle caches, rebuild bundle, and reload current shell"
    echo "🗑  Clearing caches..."
    rm -f ~/.cache/gopass/shell-env
    rm -f ~/.cache/fish/config_bundle.fish

    fish_bundle_rebuild
    or return 1

    echo ""
    echo "🔄 Reloading current shell..."
    source ~/.cache/fish/config_bundle.fish
    echo "✓ Done"
end
