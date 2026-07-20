#!/usr/bin/env bash
# Git helpers for listing and reviewing author-scoped file changes.

# -----------------------------------------------------------------------------
# git-ls — list unique files changed by the current Git author
#
# Prints a sorted, deduplicated list of file paths touched by commits from
# `git config user.email` within an optional date range (defaults to today).
#
# Options:
#   -c, -commit  <rev>     Starting revision for git log (default: HEAD)
#   -s, -since   <date>    Inclusive start date YYYY-MM-DD (default: today)
#   -e, -until   <date>    Inclusive end date YYYY-MM-DD (default: today)
#   -x, -exclude <path>    Pathspec to exclude from results
#   -g, -grep    <text>    Only commits whose message matches text (ignorecase)
#
# Options accept either `-flag=value` or `-flag value` forms.
#
# Example:
#   git-ls -since=2026-07-01 -until=2026-07-18 -exclude=vendor/
#   git-ls -grep=fix
# -----------------------------------------------------------------------------
git-ls() {
    local commit="HEAD"
    local since
    local until
    local exclude=""
    local grep_text=""
    local author
    since=$(date +%Y-%m-%d)
    until=$(date +%Y-%m-%d)
    author=$(git config user.email)

    while [ $# -gt 0 ]; do
        case "$1" in
            -commit=*|-c=*)  commit="${1#*=}"; shift ;;
            -since=*|-s=*)   since="${1#*=}"; shift ;;
            -until=*|-e=*)   until="${1#*=}"; shift ;;
            -exclude=*|-x=*) exclude="${1#*=}"; shift ;;
            -grep=*|-g=*)    grep_text="${1#*=}"; shift ;;
            -commit|-c)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                commit="$2"; shift 2
                ;;
            -since|-s)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                since="$2"; shift 2
                ;;
            -until|-e)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                until="$2"; shift 2
                ;;
            -exclude|-x)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                exclude="$2"; shift 2
                ;;
            -grep|-g)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                grep_text="$2"; shift 2
                ;;
            *)
                echo "Warning: Unknown argument '$1' ignored." >&2
                shift
                ;;
        esac
    done

    # Array keeps date values with spaces as a single git argument
    local -a args=("$commit" "--author=$author" --name-only --pretty=format:)
    [ -n "$since" ] && args+=(--since="$since 00:00:00")
    [ -n "$until" ] && args+=(--until="$until 23:59:59")
    if [ -n "$grep_text" ]; then
        args+=(--grep="$grep_text" -i)
    fi

    if [ -n "$exclude" ]; then
        git log "${args[@]}" -- ":(exclude)$exclude"
    else
        git log "${args[@]}"
    fi | grep -v '^$' | sort -u
}

# -----------------------------------------------------------------------------
# git-dif — open git-ls results in git difftool
#
# Collects files from git-ls (same options) and launches `git difftool` against
# the chosen commit so you can review those author-scoped changes interactively.
# Prints a message and exits if no matching files are found.
#
# Options:
#   Same as git-ls (-commit/-c, -since/-s, -until/-e, -exclude/-x, -grep/-g).
#   -c/-commit also selects the revision passed to git difftool (default: HEAD).
#
# Example:
#   git-dif -since=2026-07-01 -c HEAD~3
#   git-dif -grep=hotfix
# -----------------------------------------------------------------------------
git-dif() {
    local -a files=()
    local file
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(git-ls "$@")

    local commit="HEAD"
    while [ $# -gt 0 ]; do
        case "$1" in
            -commit=*|-c=*) commit="${1#*=}"; shift ;;
            -commit|-c)
                [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; return 1; }
                commit="$2"; shift 2
                ;;
            *) shift ;;
        esac
    done

    if [ ${#files[@]} -gt 0 ]; then
        git difftool "$commit" -- "${files[@]}"
    else
        echo "No files modified matching the criteria."
    fi
}
