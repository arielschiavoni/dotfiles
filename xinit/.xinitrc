xrdb -merge ~/.Xresources
xinput set-prop "Logitech M510" "libinput Natural Scrolling Enabled" 1
setxkbmap -option compose:ralt

exec bspwm
