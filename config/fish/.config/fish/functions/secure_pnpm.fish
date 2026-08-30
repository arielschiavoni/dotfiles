function secure_pnpm -d "pnpm wrapper that scans for vulnerabilities before running install scripts"
    # Installs with --ignore-scripts first, scans the tree with trivy, and only
    # then runs the package build scripts via `pnpm rebuild`. This prevents a
    # malicious postinstall from executing before it has been scanned.
    #
    # Pass --skip-trivy to bypass the scan.

    set -l cmd $argv[1]
    set -l args $argv[2..-1]

    set -l skip_trivy false
    if contains -- --skip-trivy $argv
        set skip_trivy true
        set -l filtered
        for arg in $args
            test "$arg" = --skip-trivy; or set -a filtered $arg
        end
        set args $filtered
    end

    # Anything that is not an install is passed straight through.
    if not contains -- "$cmd" install i add
        command pnpm $cmd $args
        return $status
    end

    if $skip_trivy
        echo "Warning: skipping security scan. Use with caution."
        command pnpm $cmd $args
        return $status
    end

    if not command -q trivy
        echo "Trivy is not installed. Please install Trivy to use this wrapper." >&2
        return 1
    end

    command pnpm $cmd $args --ignore-scripts
    or return $status

    if not trivy fs --scanners vuln --exit-code 1 --severity HIGH,CRITICAL .
        echo "Trivy reported vulnerabilities or the scan failed. Review the results." >&2
        return 1
    end

    # pnpm has no way to re-run install scripts, so build explicitly.
    echo "No vulnerabilities found. Running package build scripts..."
    command pnpm rebuild
end
