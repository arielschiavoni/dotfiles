function secure_npm --description "Secure npm wrapper that scans for vulnerabilities before running scripts"
    # Store the first argument as the npm command (e.g., "install", "i", "ci", "run", etc.)
    # $argv is Fish's equivalent to Bash's $@, containing all function arguments
    # $argv[1] gets the first argument
    set -l cmd $argv[1]

    # Store the remaining arguments (everything after the first argument)
    # $argv[2..-1] is a slice: from index 2 to the end (-1)
    # -l flag makes the variable local to this function
    set -l args $argv[2..-1]

    # Check if the command is one of the install commands
    # "test" is Fish's conditional operator (like Bash's [ or [[ )
    # "or" is Fish's logical OR operator (Bash uses ||)
    if test "$cmd" = install; or test "$cmd" = i; or test "$cmd" = ci
        # Check if trivy is installed and available in PATH
        # "not" negates the condition (Bash uses !)
        # "command -v" checks if a command exists
        # >/dev/null 2>&1 redirects output to suppress it
        if not command -v trivy >/dev/null 2>&1
            echo "Trivy is not installed. Please install Trivy to use this script."
            # return 1 exits the function with error status (non-zero)
            return 1
        end

        # First run: Install packages WITHOUT running any npm scripts
        # This prevents potentially malicious scripts from running before security scan
        # "command" ensures we use the actual npm binary, not any alias
        command npm $cmd $args --ignore-scripts

        # Run Trivy security scanner on the current directory
        # --scanners vuln: only scan for vulnerabilities
        # -q: quiet mode
        # --no-progress: don't show progress bar
        # --exit-code 1: exit with code 1 if vulnerabilities found
        # --severity HIGH,CRITICAL: only report high/critical issues
        # "not" inverts the exit code - if scan fails or finds issues, the condition is true
        if not trivy fs --scanners vuln --exit-code 1 --severity HIGH,CRITICAL .
            echo "Trivy reported vulnerabilities or scan failed. Review results."
            return 1
        end

        # If we reach here, no vulnerabilities were found
        # Now run npm install again WITH scripts enabled
        # --no-audit skips npm's built-in audit (we already scanned with Trivy)
        echo "No vulnerabilities found. Re-running npm install with scripts enabled..."
        command npm $cmd $args --no-audit
    else
        # For any other npm commands (not install/i/ci), just pass them through directly
        # This includes: npm run, npm test, npm publish, etc.
        command npm $cmd $args
    end
end
