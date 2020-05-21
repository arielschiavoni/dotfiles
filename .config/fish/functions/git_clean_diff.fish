function git_clean_diff --description 'Get a file diff without the default git diff headers, context and +/- signs'
	# git diff --unified=0 --word-diff=color $argv | tail +6
	# git diff --unified=0 $argv | tail +6 | sed -r "s/^([^-+ ]*)[-+ ]/\\1/"
	git diff --unified=0 $argv | tail +6 | sed -r "s/^([^-+ ]*)[-+ ]/\\1/"
end
