#!/usr/bin/env bash
# Interactively review and delete git worktrees, grouped by whether their
# branch is merged into the main branch or still has an open PR.
set -uo pipefail

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_GRAY=$'\033[90m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_GRAY=""; C_CYAN=""
fi

usage() { echo "Usage: $(basename "$0") [-n|--dry-run] [-l|--limit N]" >&2; exit 1; }

dry_run=0
limit=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) dry_run=1 ;;
    -l|--limit) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; limit="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

# --- discover worktrees -----------------------------------------------------

paths=()
branches=()
heads=()
lockeds=()

_flush_record() {
  if [[ -n "${cur_path:-}" ]]; then
    paths+=("$cur_path")
    branches+=("$cur_branch")
    heads+=("$cur_head")
    lockeds+=("$cur_locked")
  fi
  cur_path=""; cur_branch=""; cur_head=""; cur_locked=0
}

cur_path=""; cur_branch=""; cur_head=""; cur_locked=0
while IFS= read -r line; do
  case "$line" in
    "worktree "*) _flush_record; cur_path="${line#worktree }" ;;
    "HEAD "*) cur_head="${line#HEAD }" ;;
    "branch refs/heads/"*) cur_branch="${line#branch refs/heads/}" ;;
    "detached") cur_branch="" ;;
    "locked"*) cur_locked=1 ;;
    "") _flush_record ;;
  esac
done < <(git worktree list --porcelain)
_flush_record

if [[ ${#paths[@]} -le 1 ]]; then
  echo "No linked worktrees found (only the main worktree exists)."
  exit 0
fi

main_dir="${paths[0]}"

if (( limit > 0 && ${#paths[@]} - 1 > limit )); then
  echo "Only checking the first $limit of $((${#paths[@]} - 1)) linked worktrees."
  paths=("${paths[@]:0:$((limit + 1))}")
  branches=("${branches[@]:0:$((limit + 1))}")
  heads=("${heads[@]:0:$((limit + 1))}")
  lockeds=("${lockeds[@]:0:$((limit + 1))}")
fi

# --- figure out the main branch and refresh remote state --------------------

main_branch="$(git -C "$main_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed -E 's@^refs/remotes/origin/@@')"
main_branch="${main_branch:-master}"

echo "Main worktree:  $main_dir"
echo "Main branch:    $main_branch"
git -C "$main_dir" fetch origin "$main_branch" --quiet 2>/dev/null \
  && echo "${C_GREEN}Fetched latest origin/$main_branch.${C_RESET}" \
  || echo "${C_YELLOW}Warning: could not fetch origin/$main_branch (using local ref, may be stale).${C_RESET}"

origin_url="$(git -C "$main_dir" config --get remote.origin.url 2>/dev/null || true)"
gh_repo="$(printf '%s' "$origin_url" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#; s#\.git$##')"
have_gh=0
if command -v gh >/dev/null 2>&1 && [[ -n "$gh_repo" ]]; then
  have_gh=1
fi

# PR lookup table as branch<TAB>state<TAB>number<TAB>title, newest first: one bulk
# call for my PRs, then parallel per-branch calls for any branch not in it.
pr_jq='.[] | [.headRefName, .state, (.number|tostring), .title] | @tsv'
prs=""
if [[ $have_gh -eq 1 ]]; then
  echo "Fetching your PRs from $gh_repo..."
  prs="$(gh pr list --repo "$gh_repo" --author @me --state all --limit 1000 \
    --json headRefName,number,state,title --jq "$pr_jq" 2>/dev/null || true)"

  missing=()
  for ((i = 1; i < ${#paths[@]}; i++)); do
    b="${branches[$i]}"
    [[ -n "$b" ]] || continue
    printf '%s\n' "$prs" | awk -F'\t' -v b="$b" '$1 == b { found = 1; exit } END { exit !found }' || missing+=("$b")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Looking up ${#missing[@]} other branches..."
    prs+=$'\n'"$(printf '%s\0' "${missing[@]}" | GH_REPO_ARG="$gh_repo" PR_JQ="$pr_jq" xargs -0 -n 1 -P 8 \
      sh -c 'gh pr list --repo "$GH_REPO_ARG" --head "$1" --state all --limit 1 --json headRefName,number,state,title --jq "$PR_JQ" 2>/dev/null' _)"
  fi
fi

echo "Checking $((${#paths[@]} - 1)) worktrees for uncommitted changes..."
dirty_paths="$(printf '%s\0' "${paths[@]:1}" | xargs -0 -n 1 -P 8 \
  sh -c '[ -d "$1" ] && [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ] && printf "%s\n" "$1"' _)"

# --- classify each linked worktree ------------------------------------------

categories=()   # MERGED | OPEN_PR | CLOSED | WIP | REVIEW | DETACHED
pr_infos=()
dirty_flags=()
old_history_flags=()
me="$(git -C "$main_dir" config user.email)"

for ((i = 1; i < ${#paths[@]}; i++)); do
  path="${paths[$i]}"
  branch="${branches[$i]}"
  head="${heads[$i]}"

  [[ -t 2 ]] && printf '\r\033[K[%d/%d] %s' "$i" "$((${#paths[@]} - 1))" "${branch:-$path}" >&2

  dirty=0
  if printf '%s\n' "$dirty_paths" | grep -Fxq -- "$path"; then
    dirty=1
  fi
  dirty_flags+=("$dirty")

  # No common ancestor = cut before master's history was rewritten; can't rebase.
  old_history=0
  git -C "$main_dir" merge-base "$head" "origin/$main_branch" >/dev/null 2>&1 || old_history=1
  old_history_flags+=("$old_history")

  if [[ -z "$branch" ]]; then
    categories+=("DETACHED")
    pr_infos+=("(detached HEAD)")
    continue
  fi

  is_merged=0
  if git -C "$main_dir" merge-base --is-ancestor "$head" "origin/$main_branch" 2>/dev/null; then
    is_merged=1
  fi

  pr_line=""
  pr_state=""
  if [[ $have_gh -eq 1 ]]; then
    pr_row="$(printf '%s\n' "$prs" | awk -F'\t' -v b="$branch" '$1 == b { print; exit }')"
    if [[ -n "$pr_row" ]]; then
      IFS=$'\t' read -r _ pr_state pr_num pr_title <<< "$pr_row"
      pr_line="PR #$pr_num ($pr_state): $pr_title"
    fi
  fi

  if [[ $is_merged -eq 1 || "$pr_state" == "MERGED" ]]; then
    categories+=("MERGED")
    [[ -n "$pr_line" ]] && pr_infos+=("$pr_line") || pr_infos+=("merged into $main_branch")
  elif [[ "$pr_state" == "OPEN" ]]; then
    categories+=("OPEN_PR")
    pr_infos+=("$pr_line")
  else
    # Review checkouts carry only other people's commits.
    mine="$(git -C "$main_dir" rev-list --count --author="$me" "origin/$main_branch..$head" 2>/dev/null || echo 0)"
    if [[ "$mine" -eq 0 ]]; then
      categories+=("REVIEW")
      [[ -n "$pr_line" ]] && pr_infos+=("$pr_line") || pr_infos+=("none of your commits")
    elif [[ "$pr_state" == "CLOSED" ]]; then
      categories+=("CLOSED")
      pr_infos+=("$pr_line")
    else
      categories+=("WIP")
      pr_infos+=("$mine of your commits, no PR")
    fi
  fi
done
[[ -t 2 ]] && printf '\r\033[K' >&2

# --- print grouped listing ---------------------------------------------------

echo
disp_to_idx=()   # display number -> original worktree index (into paths/branches/...)
disp_counter=0

print_group() {
  local label="$1" want="$2" color="$3" any=0 out=""
  for ((i = 1; i < ${#paths[@]}; i++)); do
    idx=$((i - 1))
    [[ "${categories[$idx]}" == "$want" ]] || continue
    any=1
    disp_counter=$((disp_counter + 1))
    disp_to_idx[$disp_counter]="$i"
    flags=""
    [[ "${lockeds[$i]}" -eq 1 ]] && flags+=" ${C_RED}${C_BOLD}[LOCKED]${C_RESET}"
    [[ "${dirty_flags[$idx]}" -eq 1 ]] && flags+=" ${C_RED}${C_BOLD}[DIRTY]${C_RESET}"
    [[ "${old_history_flags[$idx]}" -eq 1 ]] && flags+=" ${C_GRAY}[OLD HISTORY]${C_RESET}"
    num="${color}${C_BOLD}${disp_counter}${C_RESET}"
    out+="$(printf "  [%s] %s (%s)%s\n      %s\n" "$num" "${paths[$i]}" "${branches[$i]:-detached}" "$flags" "${pr_infos[$idx]}")"$'\n'
  done
  [[ $any -eq 0 ]] && return
  echo "${C_BOLD}${color}== $label ==${C_RESET}"
  printf '%s' "$out"
  echo
}

print_group "Merged into $main_branch — safe to delete" "MERGED" "$C_GREEN"
print_group "Open PR — still active" "OPEN_PR" "$C_YELLOW"
print_group "Closed PR, your work — might want it back" "CLOSED" "$C_RED"
print_group "Your commits, no PR — WIP" "WIP" "$C_RED"
print_group "Review checkouts — none of your commits" "REVIEW" "$C_GRAY"
print_group "Detached HEAD" "DETACHED" "$C_GRAY"

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: no changes made."
  exit 0
fi

# --- prompt for deletion ------------------------------------------------------

# Drop anything typed while the scan ran (e.g. Enter to check it was alive),
# so it can't answer the prompt below.
if [[ -t 0 ]]; then
  old_stty="$(stty -g)"
  stty -icanon min 0 time 0
  cat >/dev/null
  stty "$old_stty"
fi

echo "${C_CYAN}Enter worktrees to delete: numbers or ranges (e.g. 3 7 12-20), and/or 'merged', 'closed', 'wip', 'review', 'detached' for a whole group. 'q' to quit:${C_RESET}"
read -r selection
selection="${selection//,/ }"

if [[ -z "$selection" || "$selection" == "q" ]]; then
  echo "No changes made."
  exit 0
fi

to_remove=()
seen=" "
_select() {
  [[ "$seen" == *" $1 "* ]] && return
  seen+="$1 "
  to_remove+=("$1")
}
_select_category() {
  for ((n = 1; n <= disp_counter; n++)); do
    i="${disp_to_idx[$n]}"
    [[ "${categories[$((i - 1))]}" == "$1" ]] && _select "$i"
  done
}

for tok in $selection; do
  case "$tok" in
    merged) _select_category MERGED ;;
    closed) _select_category CLOSED ;;
    wip) _select_category WIP ;;
    review) _select_category REVIEW ;;
    detached) _select_category DETACHED ;;
    *)
      if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        lo="${BASH_REMATCH[1]}"; hi="${BASH_REMATCH[2]}"
      elif [[ "$tok" =~ ^[0-9]+$ ]]; then
        lo="$tok"; hi="$tok"
      else
        echo "Skipping invalid selection: $tok"
        continue
      fi
      for ((n = lo; n <= hi; n++)); do
        if (( n >= 1 && n <= disp_counter )); then
          _select "${disp_to_idx[$n]}"
        else
          echo "Skipping out-of-range number: $n"
        fi
      done
      ;;
  esac
done

if [[ ${#to_remove[@]} -eq 0 ]]; then
  echo "Nothing valid selected. No changes made."
  exit 0
fi

removed_merged_branches=()
trash_dirs=()

for i in "${to_remove[@]}"; do
  path="${paths[$i]}"
  branch="${branches[$i]}"
  idx=$((i - 1))
  locked="${lockeds[$i]}"
  dirty="${dirty_flags[$idx]}"

  echo
  echo "${C_BOLD}-- $path (${branch:-detached}) --${C_RESET}"

  if [[ "$locked" -eq 1 ]]; then
    read -r -p "  ${C_RED}This worktree is LOCKED. Unlock and remove it? [y/N]${C_RESET} " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      git -C "$main_dir" worktree unlock "$path" 2>/dev/null || true
    else
      echo "  Skipped."
      continue
    fi
  fi

  if [[ "$dirty" -eq 1 ]]; then
    echo "  ${C_RED}${C_BOLD}WARNING: this worktree has uncommitted changes.${C_RESET}"
    read -r -p "  ${C_RED}Force-remove anyway and LOSE those changes? [y/N]${C_RESET} " ans
    if ! [[ "$ans" =~ ^[Yy]$ ]]; then
      echo "  Skipped."
      continue
    fi
  fi

  # `git worktree remove` re-checks status and unlinks every file (~1 min each
  # in payaus). Rename into a sibling trash dir instead (instant, same disk),
  # prune git's records afterwards, and delete the files in the background.
  trash_dir="$(dirname "$path")/.worktree-trash"
  if [[ -d "$path" ]]; then
    mkdir -p "$trash_dir" && mv "$path" "$trash_dir/$(basename "$path").$$.$RANDOM" || {
      echo "  ${C_RED}Failed to move it aside (see error above).${C_RESET}"
      continue
    }
  fi
  echo "  ${C_GREEN}Removed.${C_RESET}"
  [[ " ${trash_dirs[*]-} " == *" $trash_dir "* ]] || trash_dirs+=("$trash_dir")
  [[ "${categories[$idx]}" == "MERGED" && -n "$branch" ]] && removed_merged_branches+=("$branch")
done

git -C "$main_dir" worktree prune

if [[ ${#trash_dirs[@]} -gt 0 ]]; then
  for d in "${trash_dirs[@]}"; do
    nohup rm -rf "$d" >/dev/null 2>&1 &
  done
  echo
  echo "${C_GRAY}Deleting removed files in the background: ${trash_dirs[*]}${C_RESET}"
fi

if [[ ${#removed_merged_branches[@]} -gt 0 ]]; then
  echo
  echo "These removed worktrees had branches already merged into $main_branch:"
  for b in "${removed_merged_branches[@]}"; do echo "  - $b"; done
  # -D because PRs are squash-merged: master never contains the branch commits,
  # so -d only passes while origin/<branch> still exists.
  read -r -p "Also force-delete these local branches (-D)? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    for b in "${removed_merged_branches[@]}"; do
      git -C "$main_dir" branch -D "$b" && echo "  Deleted branch $b" || echo "  Could not delete branch $b"
    done
  fi
fi
