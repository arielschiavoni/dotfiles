function fish_bundle_rebuild -d "Rebuild fish configuration bundle cache"
    set -l config_dir $__fish_config_dir
    set -l cache_dir ~/.cache/fish
    set -l bundle_file $cache_dir/config_bundle.fish

    echo "🔧 Rebuilding fish config bundle..."

    # Validate cache directory is writable
    if not test -d $cache_dir
        mkdir -p $cache_dir 2>/dev/null
        if test $status -ne 0
            echo "❌ Error: Cannot create cache directory: $cache_dir" >&2
            return 1
        end
    end

    if not test -w $cache_dir
        echo "❌ Error: Cache directory is not writable: $cache_dir" >&2
        return 1
    end

    # Build bundle
    set -l temp_bundle $bundle_file.tmp

    # Add header
    echo "# Fish Config Bundle - Auto-generated" >$temp_bundle
    echo "# Generated: "(date "+%Y-%m-%d %H:%M:%S") >>$temp_bundle
    echo "# Rebuild with: fish_bundle_rebuild" >>$temp_bundle
    echo "# DO NOT EDIT - Changes will be overwritten" >>$temp_bundle
    echo "" >>$temp_bundle

    echo "📦 Bundling configuration files..."
    set -l file_count 0

    # === 1. Homebrew initialization (MUST be first) ===
    # Homebrew provides the PATH and environment variables that all other tools depend on.
    # We need to evaluate it in the current shell so subsequent tool commands can be found.
    echo "   • Homebrew environment"
    echo "" >>$temp_bundle
    echo "# === Homebrew Environment ===" >>$temp_bundle
    if test (uname) = Darwin; and test -x /opt/homebrew/bin/brew
        echo "# Homebrew paths and environment" >>$temp_bundle
        /opt/homebrew/bin/brew shellenv fish >>$temp_bundle
        
        # Source brew environment in THIS shell so subsequent commands are found
        eval (/opt/homebrew/bin/brew shellenv fish)
        
        set file_count (math $file_count + 1)
    else
        echo "# Homebrew not found, skipping initialization" >>$temp_bundle
    end
    echo "" >>$temp_bundle

    # === 2. Tool initializations (depend on brew paths) ===
    # These tools output shell code that gets captured and stored in the bundle.
    # On shell startup, sourcing the bundle executes all this pre-generated code
    # instead of running these initialization commands every time.
    
    # fnm (Fast Node Manager)
    if command -q fnm
        echo "   • fnm (Node.js)"
        echo "# === fnm (Fast Node Manager) ===" >>$temp_bundle
        fnm env --use-on-cd --shell fish >>$temp_bundle
        echo "" >>$temp_bundle
        set file_count (math $file_count + 1)
    end

    # zoxide (smarter cd)
    if command -q zoxide
        echo "   • zoxide"
        echo "# === zoxide (smarter cd) ===" >>$temp_bundle
        zoxide init fish >>$temp_bundle
        echo "" >>$temp_bundle
        set file_count (math $file_count + 1)
    end

    # atuin (shell history)
    if command -q atuin
        echo "   • atuin"
        echo "# === atuin (shell history) ===" >>$temp_bundle
        atuin init fish >>$temp_bundle
        echo "" >>$temp_bundle
        set file_count (math $file_count + 1)
    end

    # starship (prompt)
    if command -q starship
        echo "   • starship"
        echo "# === starship (prompt) ===" >>$temp_bundle
        starship init fish --print-full-init >>$temp_bundle
        echo "" >>$temp_bundle
        set file_count (math $file_count + 1)
    end

    # === 3. Static configuration files from bundle.d ===
    # These are copied as-is since they contain static aliases, abbreviations,
    # and keybindings that don't need to be generated at bundle time.
    for file in $config_dir/bundle.d/*.fish
        if test -f $file
            set -l basename (basename $file)
            echo "   • $basename"
            echo "# === $basename ===" >>$temp_bundle
            cat $file >>$temp_bundle
            echo "" >>$temp_bundle
            set file_count (math $file_count + 1)
        end
    end

    # Write bundle file atomically
    mv $temp_bundle $bundle_file
    if test $status -ne 0
        echo "❌ Error: Failed to write bundle file" >&2
        rm -f $temp_bundle
        return 1
    end

    # Report results
    set -l bundle_size (du -h $bundle_file | awk '{print $1}')
    echo ""
    echo "✓ Bundle created: $bundle_file ($bundle_size)"
    echo "⚡ Bundled $file_count components"
    echo ""
    echo "Tip: Reload shell to use the new bundle"
end
