#!/bin/bash

# Terminate already running bar instances
killall -q polybar

# Launch Polybar, using default config location ~/.config/polybar/config
echo "---" | tee -a /tmp/polybar_topbar.log
polybar topbar >/tmp/polybar_topbar.log 2>&1 &

echo "Polybar launched..."
