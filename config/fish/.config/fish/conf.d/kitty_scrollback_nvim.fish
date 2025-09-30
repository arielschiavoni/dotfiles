# ~/.config/fish/conf.d/kitty_scrollback_nvim.fish
function kitty_scrollback_edit_command_buffer
    set --local --export VISUAL "$HOME/.local/share/nvim/lazy/kitty-scrollback.nvim/scripts/edit_command_line.sh"
    edit_command_buffer
    commandline ''
end

bind --mode default ctrl-e kitty_scrollback_edit_command_buffer
bind --mode visual ctrl-e kitty_scrollback_edit_command_buffer
bind --mode insert ctrl-e kitty_scrollback_edit_command_buffer
