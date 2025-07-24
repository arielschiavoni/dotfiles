function fish_title
    # show the name of the process or just fish, truncated to the first word
    set -l title_text

    # Check if argv[1] exists. If not, default to "fish".
    if test -n "$argv[1]"
        # Extract only the first word from argv[1].
        # For example, if argv[1] is "git log", this will result in "git".
        set title_text (string split ' ' -- $argv[1])[1]
    else
        # Fallback if no command argument is provided (e.g., in a new shell session)
        set title_text fish
    end

    echo $title_text
end
