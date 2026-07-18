git-ls() {
    local commit="HEAD"
    local since
    local until
    local exclude=""
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

    if [ -n "$exclude" ]; then
        git log "${args[@]}" -- ":(exclude)$exclude"
    else
        git log "${args[@]}"
    fi | grep -v '^$' | sort -u
}

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

