function pi_translate -d "pi as a German translator/tutor"
    pi --no-extensions --no-skills --no-prompt-templates --no-context-files \
        --extension ~/.pi/agent/translator/translate.ts $argv
end
