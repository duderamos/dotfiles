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

# --- classify each linked worktree ------------------------------------------

categories=()   # MERGED | OPEN_PR | STALE | DETACHED
pr_infos=()
dirty_flags=()

for ((i = 1; i < ${#paths[@]}; i++)); do
  path="${paths[$i]}"
  branch="${branches[$i]}"
  head="${heads[$i]}"

  dirty=0
  if [[ -d "$path" ]] && [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
    dirty=1
  fi
  dirty_flags+=("$dirty")

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
    pr_json="$(gh pr list --repo "$gh_repo" --head "$branch" --state all --json number,state,title,url --limit 1 2>/dev/null || true)"
    if [[ -n "$pr_json" && "$pr_json" != "[]" ]]; then
      pr_state="$(printf '%s' "$pr_json" | sed -nE 's/.*"state":"([A-Z]+)".*/\1/p')"
      pr_num="$(printf '%s' "$pr_json" | sed -nE 's/.*"number":([0-9]+).*/\1/p')"
      pr_title="$(printf '%s' "$pr_json" | sed -nE 's/.*"title":"([^"]*)".*/\1/p')"
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
    categories+=("STALE")
    if [[ -n "$pr_line" ]]; then
      pr_infos+=("$pr_line")
    else
      pr_infos+=("no PR found, not merged into $main_branch")
    fi
  fi
done

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
print_group "No open PR, not merged — stale/unknown" "STALE" "$C_RED"
print_group "Detached HEAD" "DETACHED" "$C_GRAY"

# --- prompt for deletion ------------------------------------------------------

echo "${C_CYAN}Enter worktree numbers to delete (space/comma separated), 'merged' for all safe-merged ones, or 'q' to quit:${C_RESET}"
read -r selection
selection="${selection//,/ }"

if [[ -z "$selection" || "$selection" == "q" ]]; then
  echo "No changes made."
  exit 0
fi

to_remove=()
if [[ "$selection" == "merged" ]]; then
  for ((n = 1; n <= disp_counter; n++)); do
    i="${disp_to_idx[$n]}"
    idx=$((i - 1))
    [[ "${categories[$idx]}" == "MERGED" ]] && to_remove+=("$i")
  done
else
  for n in $selection; do
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= disp_counter )); then
      to_remove+=("${disp_to_idx[$n]}")
    else
      echo "Skipping invalid selection: $n"
    fi
  done
fi

if [[ ${#to_remove[@]} -eq 0 ]]; then
  echo "Nothing valid selected. No changes made."
  exit 0
fi

removed_merged_branches=()

for i in "${to_remove[@]}"; do
  path="${paths[$i]}"
  branch="${branches[$i]}"
  idx=$((i - 1))
  locked="${lockeds[$i]}"
  dirty="${dirty_flags[$idx]}"

  echo
  echo "${C_BOLD}-- $path (${branch:-detached}) --${C_RESET}"

  force_args=()

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
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      force_args=(--force)
    else
      echo "  Skipped."
      continue
    fi
  fi

  if git -C "$main_dir" worktree remove "${force_args[@]}" "$path"; then
    echo "  ${C_GREEN}Removed.${C_RESET}"
    [[ "${categories[$idx]}" == "MERGED" && -n "$branch" ]] && removed_merged_branches+=("$branch")
  else
    echo "  ${C_RED}Failed to remove (see error above).${C_RESET}"
  fi
done

if [[ ${#removed_merged_branches[@]} -gt 0 ]]; then
  echo
  echo "These removed worktrees had branches already merged into $main_branch:"
  for b in "${removed_merged_branches[@]}"; do echo "  - $b"; done
  read -r -p "Also delete these local branches (safe -d delete)? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    for b in "${removed_merged_branches[@]}"; do
      git -C "$main_dir" branch -d "$b" && echo "  Deleted branch $b" || echo "  Could not delete branch $b"
    done
  fi
fi
