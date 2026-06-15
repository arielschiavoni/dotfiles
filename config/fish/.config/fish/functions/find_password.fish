function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
    set selection (gopass ls --flat | fzf --preview "gopass show {}")

    if test $selection
        if test (uname) = Darwin
            gopass show $selection | pbcopy
        else if string match -q "*Linux*" (uname)
            gopass show $selection | wl-copy
        end
    end
end
