function kitty_session -d 'Creates a new kitty window from a recent visited folder'
    # Define folders with their specific prefix and ANSI colors
    set folders (zoxide query --list | string replace --all "$HOME" '~' | sed 's/^/\x1b[34m \x1b[0m /')

    # Define sessions with their specific prefix and ANSI colors, including an index
    set raw_session_titles (kitten @ ls | jq -r '.[].tabs[0].title')
    set formatted_sessions_with_index
    set i 1
    for title in $raw_session_titles
        set formatted_sessions_with_index $formatted_sessions_with_index (printf "\x1b[32m󰖳 \x1b[0m%s - %d" "$title" "$i")
        set i (math "$i + 1")
    end
    set sessions (string join \n $formatted_sessions_with_index)

    # Concatenate the formatted folders and sessions, each on a new line, before piping to fzf.
    set selection (string join \n $sessions $folders | fzf --ansi)

    # Only proceed if a selection was made
    if test -n "$selection"
        # Check if the selected fzf entry starts with the window character (session) and capture the index
        set session_matches (string match -rg '^󰖳 .*\s-\s([0-9]+)$' "$selection")

        if test -n "$session_matches"
            # select the os_window using the captured index
            kitten @ action nth_os_window $session_matches[1]
        else
            # Extract the folder path and replace '~' with $HOME
            set folder_path (string replace --regex "^  " "" "$selection")
            set folder_path (string replace --all '~' "$HOME" "$folder_path")
            # Extract the folder name for the tab title (last two path components)
            set components (string split '/' "$folder_path")
            set folder_name (string join '/' $components[-2..])
            # Create a new kitty os_window with a tab using the folder name in the directory specified
            kitty @ launch --type=os-window --tab-title "$folder_name" --cwd "$folder_path"
        end
    else
        echo "No selection made. Aborting."
    end
end
