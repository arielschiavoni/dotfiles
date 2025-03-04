#!/bin/bash

#!/bin/bash

# Store the original directory
original_dir=$(pwd)

# Change to the parent directory
cd ../ || {
  echo "Error: Could not change to parent directory."
  exit 1
}

# Run stow
stow --target ~ \
	bat \
	git || {
  echo "Error: Stow command failed."
  cd "$original_dir" # Return to original directory even on failure
  exit 1
}

# Change back to the original directory
cd "$original_dir" || {
  echo "Error: Could not return to original directory."
  exit 1
}

echo "Stow operation completed successfully."

