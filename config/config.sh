#!/bin/bash


OS=$(uname -s)

if [[ "$OS" == Linux* ]]; then
  echo "Linux"
  # exclude Darwin only package
  dirs=$(find . -maxdepth 1 -type d | grep -v -e "aerospace" -e "^\.$" | sed 's/^.\///')
else
  echo "Configuring Darwin"
  dirs=$(find . -maxdepth 1 -type d | grep -v -e "^\.$" | sed 's/^.\///')
fi

stow --target ~ $dirs
echo "The following directories have been linked with to the ~/.config folder"
echo "$dirs"

