# ~/.aws/{config,credentials} from gopass (personal/dotfiles/aws/*).
#
# Neither file is in this repo: the credentials file holds access keys, and the
# config file holds account IDs, role names and SSO start URLs. gopass is the
# source of truth; these are 0600 working copies, because every AWS SDK reads a
# path and takes nothing else.
#
# Written only when absent, so the steady state is two `test -f` builtins and
# no process at all. To pick up a change, edit it in gopass and delete the
# local file:
#
#   gopass edit personal/dotfiles/aws/config; and rm ~/.aws/config
#
# Deliberately NOT guarded by `status is-interactive`: a `fish -c` on a fresh
# machine should be able to bootstrap ~/.aws too.
if command -q gopass
    for name in config credentials
        set -l file ~/.aws/$name
        test -f $file; and continue

        mkdir -p ~/.aws
        chmod 700 ~/.aws

        # Create empty, restrict, then fill: the file is never both readable
        # and populated. `show -n -f` disables gopass's key/value parsing and
        # its safecontent redaction, which is what makes the read verbatim.
        set -l tmp $file.tmp
        rm -f $tmp
        touch $tmp
        chmod 600 $tmp
        if gopass show -n -f personal/dotfiles/aws/$name >$tmp 2>/dev/null
            and test -s $tmp
            mv $tmp $file
            echo "gopass: wrote $file"
        else
            rm -f $tmp
        end
    end
end
