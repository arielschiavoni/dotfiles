function pi_translate -d "pi as a German translator/tutor (sandboxed)"
    # pi-safe needs a project dir; use an empty scratch one
    set -l dir ~/.local/state/pi-translate
    mkdir -p $dir
    # env -C: run pi-safe in $dir without changing the shell's cwd
    env -C $dir pi-safe --no-extensions --no-skills --no-prompt-templates --no-context-files \
        --extension ~/.pi/agent/translator/translate.ts \
        --extension ~/.pi/agent/extensions/pi-safe-indicator.ts $argv
end
