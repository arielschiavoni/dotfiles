# === Bundle Cache Loader ===
# Set FISH_NO_BUNDLE=1 to bypass cache during development
# Run 'fish_bundle_rebuild' after editing conf.d files
if test -z "$FISH_NO_BUNDLE"
    set -l bundle_cache ~/.cache/fish/config_bundle.fish

    if test -f $bundle_cache
        # Fast path: use cached bundle
        source $bundle_cache
    else
        # Bundle doesn't exist - auto-rebuild on first start
        echo "⚡ Building fish config cache for faster startup..." >&2
        fish_bundle_rebuild

        if test -f $bundle_cache
            source $bundle_cache
            echo "✓ Cache built successfully! Future shells will be faster." >&2
        else
            echo "⚠️  Bundle creation failed. Loading configuration normally..." >&2
            # Fish will auto-load conf.d/* as fallback
        end
    end
else
    # Development mode: skip bundle
    echo "🔧 Development mode: bundle bypassed (FISH_NO_BUNDLE=1)" >&2
end
