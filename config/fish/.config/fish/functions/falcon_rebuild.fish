function falcon_rebuild --argument directory -d "Deletes node_modules, .wireit and dist folders and rebuilds the project"
  fd --no-ignore --hidden --type d "node_modules" --prune . | xargs --verbose --max-procs 0 -I DIR rm -rf DIR
  fd --no-ignore --hidden --type d "(.wireit|dist)" --prune . | xargs --max-procs 0 --verbose -I DIR rm -rf DIR
  npm ci
  npm run build
end
