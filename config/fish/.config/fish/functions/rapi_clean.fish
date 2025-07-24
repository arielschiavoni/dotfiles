function rapi_clean --argument directory -d "Cleanup up renderer-api project and builds it"
    fd --no-ignore --hidden --type d node_modules --prune . | xargs --verbose --max-procs 0 -I DIR rm -rf DIR
    fd --no-ignore --hidden --type d "(.wireit|dist)" --prune . | xargs --max-procs 0 --verbose -I DIR rm -rf DIR
    npm ci
    npm run build --workspace=packages/renderer-api
end
