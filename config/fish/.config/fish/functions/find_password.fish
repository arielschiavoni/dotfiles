function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
  set selection (gopass ls --flat | fzf --preview "gopass show {}")

  if test $selection
    set password (gopass show $selection)

    if test (uname) = "Darwin"
      echo $password | pbcopy
    else if string match -q "*Linux*" (uname)
      echo $password | wl-copy
    end
  end
end

