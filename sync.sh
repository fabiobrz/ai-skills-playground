#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(basename "$0")"
SKILLS_DIR="$(cd "$(dirname "$0")/skills" && pwd)"

show_help() {
    cat <<EOF
Usage: $SCRIPT <command> [<action>] [<target-directory>]

Commands:
  skills add <target-dir>      Symlink skills from this repo into <target-dir>
  skills remove <target-dir>   Remove skill symlinks from <target-dir>
  help                         Show this help message
EOF
}

skills_add() {
    local target_dir="${1%/}"
    mkdir -p "$target_dir"
    for skill_path in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_path" ]] || continue
        local skill_name target_link
        skill_name="$(basename "$skill_path")"
        target_link="$target_dir/$skill_name"
        if [[ -L "$target_link" ]]; then
            echo "skip: $skill_name (symlink already exists)"
        elif [[ -e "$target_link" ]]; then
            echo "warn: $skill_name (non-symlink entry already exists, skipping)"
        else
            ln -s "$skill_path" "$target_link"
            echo "link: $skill_name -> $skill_path"
        fi
    done
}

skills_remove() {
    local target_dir="${1%/}"
    for skill_path in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_path" ]] || continue
        local skill_name target_link resolved
        skill_name="$(basename "$skill_path")"
        target_link="$target_dir/$skill_name"
        if [[ -L "$target_link" ]]; then
            resolved="$(readlink -f "$target_link")"
            if [[ "$resolved" == "$SKILLS_DIR/$skill_name" ]]; then
                rm "$target_link"
                echo "unlink: $skill_name"
            else
                echo "skip: $skill_name (symlink does not point to this repo)"
            fi
        elif [[ -e "$target_link" ]]; then
            echo "skip: $skill_name (not a symlink, leaving untouched)"
        else
            echo "skip: $skill_name (not found)"
        fi
    done
}

if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

case "$1" in
    help|-h|--help)
        show_help
        exit 0
        ;;
    skills)
        if [[ $# -ne 3 ]]; then
            echo "error: 'skills' requires an action and a target directory" >&2
            echo >&2
            show_help >&2
            exit 1
        fi
        case "$2" in
            add)    skills_add    "$3" ;;
            remove) skills_remove "$3" ;;
            *)
                echo "error: unknown action '$2' (expected: add, remove)" >&2
                echo >&2
                show_help >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "error: unknown command '$1'" >&2
        echo >&2
        show_help >&2
        exit 1
        ;;
esac
