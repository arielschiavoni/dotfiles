function find_password -d "Fuzzy searches a password in all gopass stores and copies it to the clipboard after selection"
  # disable preview of password :-)
  # gopass show --clip (gopass ls --flat | fzf)
  # redirect output to pbcopy because --clip only copies the first line!
  # gopass show --clip (gopass ls --flat | fzf --preview "gopass show {}")
  gopass show (gopass ls --flat | fzf --preview "gopass show {}") | pbcopy
end

