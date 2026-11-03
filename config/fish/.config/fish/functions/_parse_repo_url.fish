function _parse_repo_url -a input -d 'Print "org/repo" for a GitHub URL, SSH URL or org/repo shorthand'
    set -l m (string match -r -- '^(?:(?:https?://|ssh://git@|git@)?(?:www\.)?github\.com[/:])?([\w.-]+)/([\w.-]+?)(?:\.git)?(?:[/?#].*)?$' (string trim -- $input))
    or return 1
    echo $m[2]/$m[3]
end
