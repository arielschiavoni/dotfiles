#!/usr/bin/env bash
# git resign [<base>]: signs the commits in <base>..HEAD (default: the
# upstream), e.g. the unsigned ones pi-safe makes. Each commit is rebuilt with
# `git commit-tree -S` from its own tree, parents, author and message, so
# nothing is replayed: no conflicts, merge commits stay as they are. You
# become the committer; the branch moves to the signed copy.
set -euo pipefail

base=${1:-'@{upstream}'}

for state in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ -e $(git rev-parse --git-path "$state") ]]; then
    echo "git resign: a rebase, merge or cherry-pick is in progress" >&2
    exit 2
  fi
done

head=$(git rev-parse --verify HEAD)
base_commit=$(git rev-parse --verify --quiet "$base^{commit}") || {
  echo "git resign: '$base' is not a commit (no upstream? pass a base)" >&2
  exit 2
}
mapfile -t commits < <(git rev-list --reverse --topo-order "$base_commit..$head")
if ((${#commits[@]} == 0)); then
  echo "git resign: nothing to sign in $base..HEAD"
  exit 1
fi

declare -A signed
for c in "${commits[@]}"; do
  parents=()
  for p in $(git rev-list --parents -n 1 "$c" | cut -s -d' ' -f2-); do
    parents+=(-p "${signed[$p]:-$p}")
  done
  # the message is everything after the headers' blank line, byte for byte
  signed[$c]=$(
    GIT_AUTHOR_NAME=$(git log -1 --format=%an "$c") \
      GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$c") \
      GIT_AUTHOR_DATE=$(git log -1 --format=%ad --date=raw "$c") \
      git commit-tree -S "${parents[@]}" "$c^{tree}" \
      < <(git cat-file commit "$c" | sed '1,/^$/d')
  )
done

new=${signed[$head]}
ref=$(git symbolic-ref -q HEAD || echo HEAD)
git update-ref -m "resign: $base..HEAD" "$ref" "$new" "$head"
echo "signed ${#commits[@]} commit(s): ${head:0:12} -> ${new:0:12}"
