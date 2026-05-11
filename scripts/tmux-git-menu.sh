#!/usr/bin/env bash
# tmux-git-menu: quick git actions menu for tmux.
#
# Key binding is set up by tmux-git-menu.tmux.
# Sub-commands run individual actions in display-popup.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

pane_path() {
    tmux display-message -p "#{pane_current_path}"
}

default_branch() {
    local b
    b=$(git -C "$(pane_path)" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || true
    if [ -n "$b" ]; then
        echo "${b#refs/remotes/origin/}"
    else
        echo main
    fi
}

# Returns "↑A ↓B" relative to upstream, or empty if none / no upstream.
branch_position() {
    local path ahead behind
    path=$(pane_path)
    ahead=$(git -C "$path" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    behind=$(git -C "$path" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    local parts=()
    [ "${ahead:-0}" -gt 0 ]  && parts+=("#[fg=green]↑$ahead#[fg=default]")
    [ "${behind:-0}" -gt 0 ] && parts+=("#[fg=red]↓$behind#[fg=default]")
    [ ${#parts[@]} -gt 0 ] && echo " ${parts[*]}"
    return 0
}

# Returns "+A -R ?U" summary or empty string.
# Counts tracked line additions/removals (staged + unstaged) and untracked files.
git_changes() {
    local path stats added removed untracked
    path=$(pane_path)
    stats=$(git -C "$path" diff --shortstat HEAD 2>/dev/null || true)
    added=0
    removed=0
    [[ "$stats" =~ ([0-9]+)[[:space:]]+insertion ]] && added="${BASH_REMATCH[1]}"
    [[ "$stats" =~ ([0-9]+)[[:space:]]+deletion ]] && removed="${BASH_REMATCH[1]}"
    untracked=$(git -C "$path" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    local parts=()
    [ "$added" -gt 0 ]   && parts+=("#[fg=green]+$added#[fg=default]")
    [ "$removed" -gt 0 ] && parts+=("#[fg=red]-$removed#[fg=default]")
    [ "${untracked:-0}" -gt 0 ] && parts+=("#[fg=yellow]?$untracked#[fg=default]")
    [ ${#parts[@]} -gt 0 ] && echo "${parts[*]}"
    return 0
}

# Wrap a shell snippet so it runs in the current pane's cwd. On success the
# popup auto-closes after a few seconds; on error it waits for a keypress.
run_in_popup() {
    local snippet="$1"
    local path
    path=$(pane_path)
    tmux display-popup -E -w 80% -h 70% -d "$path" \
        "bash -c $(printf '%q' "$snippet"); status=\$?; echo; if [ \$status -eq 0 ]; then read -t 3 -n1 -s -r -p '[closing in 3s — press any key]' || true; else read -n1 -s -r -p '[error — any key to close]'; fi"
}

show_menu() {
    local branch default starting_choice
    branch=$(git -C "$(pane_path)" branch --show-current 2>/dev/null || true)
    default=$(default_branch)
    local header_args=()
    starting_choice=0
    if [ -n "$branch" ]; then
        local position changes
        position=$(branch_position)
        changes=$(git_changes)
        header_args+=("-#[align=centre,fg=cyan]$branch#[fg=default]$position" "" "")
        [ -n "$changes" ] && header_args+=("-#[align=centre]$changes" "" "")
        header_args+=("" "" "")
        starting_choice=$(( ${#header_args[@]} / 3 ))
    fi
    tmux display-menu \
        -T "#[align=centre] git " \
        -C "$starting_choice" \
        -- \
        "${header_args[@]}" \
        "Rebase from origin/$default" "r" "run-shell -b 'bash \"$SCRIPT\" rebase'" \
        "Checkout $default & pull"    "m" "run-shell -b 'bash \"$SCRIPT\" checkout-default'" \
        "" "" "" \
        "Switch branch"               "b" "run-shell -b 'bash \"$SCRIPT\" switch'" \
        "Pull"                        "p" "run-shell -b 'bash \"$SCRIPT\" pull'" \
        "Add (patch)"                 "a" "run-shell -b 'bash \"$SCRIPT\" add'" \
        "Reset (unstage)"             "u" "run-shell -b 'bash \"$SCRIPT\" reset'" \
        "Commit"                      "c" "run-shell -b 'bash \"$SCRIPT\" commit-prompt'" \
        "Push"                        "P" "run-shell -b 'bash \"$SCRIPT\" push'"
}

case "${1:-menu}" in
    menu)
        show_menu
        ;;
    switch)
        # fzf over local branches by recency; pick one, check it out.
        snippet='branch=$(git branch --sort=-committerdate --format="%(refname:short)" | fzf --header="Switch branch" --height=100%) && [ -n "$branch" ] && git checkout "$branch"'
        run_in_popup "$snippet"
        ;;
    pull)
        run_in_popup 'git pull'
        ;;
    add)
        run_in_popup 'git add -p'
        ;;
    reset)
        run_in_popup 'git reset'
        ;;
    checkout-default)
        snippet='default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s@^refs/remotes/origin/@@"); default=${default:-main}; echo "Checking out $default..."; echo; git checkout "$default" && git pull'
        run_in_popup "$snippet"
        ;;
    push)
        run_in_popup 'git push'
        ;;
    rebase)
        snippet='default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s@^refs/remotes/origin/@@"); default=${default:-main}; echo "Rebasing onto origin/$default..."; echo; git fetch origin && git rebase "origin/$default"'
        run_in_popup "$snippet"
        ;;
    commit-prompt)
        tmpfile=$(mktemp -t tmux-git-commit.XXXXXX)
        tmux command-prompt -p "Commit message:" \
            "run-shell -b 'echo %1 > $tmpfile && bash \"$SCRIPT\" commit $tmpfile'"
        ;;
    commit)
        msgfile="$2"
        if [ ! -s "$msgfile" ]; then
            rm -f "$msgfile"
            exit 0
        fi
        # Use -F to read the message from a file so we don't have to escape.
        snippet="git commit -F '$msgfile'; rm -f '$msgfile'"
        run_in_popup "$snippet"
        ;;
    *)
        echo "Usage: $0 [menu|switch|pull|push|rebase|commit-prompt|commit FILE]" >&2
        exit 1
        ;;
esac
