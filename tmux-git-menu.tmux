#!/usr/bin/env bash
# tmux-git-menu: quick git actions menu for tmux
#
# Configuration:
#   set -g @tmux-git-menu-key g   # key to launch the menu (default: g)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_tmux_option() {
    local value
    value=$(tmux show-options -gqv "$1")
    [ -n "$value" ] && echo "$value" || echo "$2"
}

key=$(get_tmux_option "@tmux-git-menu-key" "g")
tmux bind-key "$key" run-shell -b "bash '$CURRENT_DIR/scripts/tmux-git-menu.sh'"
