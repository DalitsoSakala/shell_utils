#!/usr/bin/env bash
# Django Makefile-style scaffolding helper
# Sourced in shell to expose the 'make-django' command.

DJANGO_REF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/django_ref.sh"
DJANGO_SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/django"

# -----------------------------------------------------------------------------
# make-django — Django model + DRF scaffolding
#
# Scaffolds a Django model and the related feature files into an existing app,
# following the conventions of the CPD Hub backend (cpd-hub/backend):
#   - models.py model class + optional Manager (managers.py)
#   - admin.py registration
#   - api/serializers.py, api/filters.py, api/views.py (DRF, enforced by default)
#   - api/urls.py router registration
#   - permissions.py permission class
#
# Usage:
#   make-django model [app.]Name [fields] [options]
#   make-django help                    Show this help
# -----------------------------------------------------------------------------

_make_django_print_help() {
    cat <<'EOF'
make-django — Django model + DRF scaffolding

Scaffolds a Django model and the related feature files into an existing app
(models.py, managers.py, admin.py, api/serializers.py, api/filters.py,
api/views.py, api/urls.py, permissions.py). Django REST Framework is used
by default; you are prompted for each piece of scaffolding, including
optional extras: ETL (data_etl/ + SQL query + pandas/polars processing
function), a Django management command, a Celery worker task registered in
developer_console/tasks.py, and frontend TypeScript API client functions +
ambient interfaces in frontend/typings/*.d.ts.

Usage:
  make-django model [app.]Name [fields] [options]
  make-django help                     Show this help message

Positional arguments:
  [app.]Name   Model name (any case: 'site', 'milk_batch' -> Site, MilkBatch).
               Prefix with 'app.' to pin the app, e.g. 'farmers.site'. If the
               app does not exist it is created via `manage.py startapp`.
  [fields]     Comma-separated fields, e.g. "name, age:Int, owner:FK:User?"

Options:
  -y, --yes     Non-interactive: create the app if needed and scaffold the
                full stack (manager, admin, serializer, viewset, filterset,
                urls, permissions, ETL, management command, Celery, TS client).
  --base CLASS  Base model class (default: BaseTimestampModel when djangondor
                is installed, else models.Model).

Field syntax (comma separated):
  name                    -> CharField(max_length=255)
  name:Type               -> typed field (Char/Text/Int/Float/Bool/Date/DateTime/
                             JSON/Array/UUID/Slug/Email/URL/File/Image/Decimal...)
  name:Type?              -> nullable field (uses **NULLABLE / **NULLABLE_CHARFIELD
                             when djangondor is installed)
  name:FK:Target          -> ForeignKey('Target', on_delete=...)
  name:FK:Target?         -> nullable ForeignKey (SET_NULL)
  name:M2M:Target         -> ManyToManyField('Target')
  name:O2O:Target         -> OneToOneField('Target')
  name:Type:opts          -> verbatim kwargs separated by ';', e.g.
                             amount:Decimal:max_digits=10;decimal_places=2
  name:CharField:200      -> CharField(max_length=200)

Examples:
  make-django model Farmer name,age:Int
  make-django model farmers.site code,name:CharField:80
  make-django model -y frost_index.Trial name,protocolOwner:FK:frost_index.User?,started:Date?
  make-django model Region code,name:CharField:80 --base models.Model
EOF
}

make-django() {
    case "${1:-}" in
        -h|-help|--help|help)
            _make_django_print_help
            return 0
            ;;
    esac

    if [ "${1:-}" = "model" ]; then
        shift
        _make_django_model "$@"
        return $?
    fi

    echo "Unknown subcommand: ${1:-}. Run 'make-django help'." >&2
    return 1
}

_make_django_pascal() {
    # "milk batch", "milk_batch", or "MilkBatch" -> "MilkBatch"
    echo "$1" | sed -E 's/[_ -]+/ /g' | awk '{
        for (i = 1; i <= NF; i++)
            printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2)
        print ""
    }'
}

_make_django_snake() {
    # "MilkBatch" -> "milk_batch"
    echo "$1" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/[- ]+/_/g' | tr '[:upper:]' '[:lower:]'
}

_make_django_kebab() {
    _make_django_snake "$1" | tr '_' '-'
}

_make_django_detect_root() {
    # Accept both layouts: manage.py in this dir, or a `backend/manage.py`
    # below it (e.g. a repo root that also contains a `frontend/` folder).
    local d="$PWD"
    while [ "$d" != "/" ]; do
        if [ -f "$d/manage.py" ]; then
            echo "$d"
            return 0
        fi
        if [ -f "$d/backend/manage.py" ]; then
            echo "$d/backend"
            return 0
        fi
        d="$(dirname "$d")"
    done
    return 1
}

_make_django_frontend_base() {
    # Plain projects keep frontend/ inside the root; cpd-hub keeps it next to
    # backend/. Return whichever exists (fall back to root/frontend).
    local root="$1"
    if [ ! -d "$root/frontend" ] && [ -d "$(dirname "$root")/frontend" ]; then
        echo "$(dirname "$root")/frontend"
    else
        echo "$root/frontend"
    fi
}

_make_django_frontend_dir() {
    # api.ts feature dir for an app.
    local root="$1" app="$2"
    echo "$(_make_django_frontend_base "$root")/src/Data/$(_make_django_kebab "$app")"
}

_make_django_typings_file() {
    # Ambient TypeScript typings live in frontend/typings/<app-name>.d.ts.
    local root="$1" app="$2"
    echo "$(_make_django_frontend_base "$root")/typings/$(_make_django_kebab "$app").d.ts"
}

_make_django_list_apps() {
    local root="$1" d base
    for d in "$root"/*/; do
        [ -d "$d" ] || continue
        [ -f "$d/models.py" ] && [ -f "$d/__init__.py" ] || continue
        base="$(basename "$d")"
        case "$base" in
            venv|.venv|__pycache__|media|logs|static|node_modules) continue ;;
        esac
        echo "$base"
    done
}

_make_django_python() {
    # Prefer the project's virtualenv interpreter so the generator can detect
    # djangondor / shared_tools / drf_spectacular in that environment.
    local root="$1"
    if [ -x "$root/.venv/bin/python" ]; then
        echo "$root/.venv/bin/python"
    elif [ -x "$root/venv/bin/python" ]; then
        echo "$root/venv/bin/python"
    else
        command -v python3 || command -v python || true
    fi
}

_make_django_confirm() {
    # Usage: _make_django_confirm "Prompt [Y/n]: "   -> 0 (yes) / 1 (no)
    local ans
    read -r -p "$1" ans
    case "$ans" in
        [yY]*) return 0 ;;
        *) return 1 ;;
    esac
}

_make_django_model() {
    local arg yes=0 base_opt=""
    local -a positional=()
    while [ "$#" -gt 0 ]; do
        arg="$1"; shift
        case "$arg" in
            -y|--yes) yes=1 ;;
            --base) base_opt="${1:-}"; shift ;;
            --base=*) base_opt="${arg#*=}" ;;
            -*) echo "Unknown option: $arg (try 'make-django help')" >&2; return 1 ;;
            *) positional+=("$arg") ;;
        esac
    done
    if [ ${#positional[@]} -gt 2 ]; then
        echo "Error: too many arguments (expected: [app.]Name [fields])." >&2
        return 1
    fi

    local root
    root="$(_make_django_detect_root)"
    if [ -z "$root" ]; then
        echo "Error: not inside a Django project (no manage.py found in this or any parent directory)." >&2
        return 1
    fi

    # --- app ------------------------------------------------------------------
    # First positional may be "Name" or "app.Name". A dotted spec pins the app,
    # creating it via `manage.py startapp` if it does not exist yet.
    local spec="${positional[0]:-}"
    local given_app="" given_name="$spec"
    if [[ "$spec" == *.* ]]; then
        given_app="${spec%.*}"
        given_name="${spec##*.}"
    fi

    local app
    if [ -n "$given_app" ]; then
        if ! [[ "$given_app" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            echo "Error: invalid app name '$given_app'." >&2
            return 1
        fi
        app="$given_app"
        if [ ! -d "$root/$app" ]; then
            local py0
            py0="$(_make_django_python "$root")"
            if [ "$yes" != 1 ] && ! _make_django_confirm "App '$app' does not exist. Create it ('manage.py startapp $app')? [y/N]: "; then
                echo "Cancelled."
                return 1
            fi
            (cd "$root" && "$py0" manage.py startapp "$app") >/dev/null || { echo "Error: failed to create app '$app'." >&2; return 1; }
            if [ ! -d "$root/$app" ]; then
                echo "Error: 'manage.py startapp $app' did not create $root/$app (is this a valid Django project?)." >&2
                return 1
            fi
            echo "Created app '$app' (manage.py startapp)."
        fi
    elif [ -f "models.py" ]; then
        app="$(basename "$PWD")"
    else
        local -a apps=()
        mapfile -t apps < <(_make_django_list_apps "$root")
        if [ ${#apps[@]} -eq 0 ]; then
            echo "Error: no Django apps found under $root." >&2
            return 1
        fi
        echo "Django apps found: ${apps[*]}"
        read -r -p "App to scaffold in [${apps[0]}]: " app
        app="${app:-${apps[0]}}"
    fi
    if [ ! -d "$root/$app" ]; then
        echo "Error: app directory '$root/$app' does not exist." >&2
        return 1
    fi

    # --- model name -------------------------------------------------------------
    local input_name="${given_name:-}"
    if [ -z "$input_name" ]; then
        read -r -p "Model name (e.g. Region): " input_name
        input_name="${input_name:-}"
    fi
    if [ -z "$input_name" ]; then
        echo "Error: model name is required." >&2
        return 1
    fi
    local Name
    Name="$(_make_django_pascal "$input_name")"

    # --- fields ---------------------------------------------------------------
    local arg_fields="${positional[1]:-}"
    if [ -z "$arg_fields" ]; then
        read -r -p "Fields (comma separated), e.g. name, age:Int, owner:FK:User?: " arg_fields
        arg_fields="${arg_fields:-}"
    fi
    if [ -z "$arg_fields" ]; then
        echo "Error: at least one field is required." >&2
        return 1
    fi
    # Normalize stray whitespace between field tokens to commas.
    arg_fields="$(echo "$arg_fields" | sed -E 's/[[:space:]]+/,/g')"

    # --- base class ------------------------------------------------------------
    local py
    py="$(_make_django_python "$root")"
    local base_default base
    if "$py" -c "import djangondor" >/dev/null 2>&1; then
        base_default="BaseTimestampModel"
    else
        base_default="models.Model"
    fi
    base="${base_opt:-}"
    if [ -z "$base" ]; then
        read -r -p "Base model class [${base_default}]: " base
        base="${base:-${base_default}}"
    fi

    # --- feature prompts --------------------------------------------------------
    local mgr=0 adm=0 ser=0 view=0 flt=0 url=0 perm=0
    local etl=0 etl_lib="pandas" sql_name="" etl_fn="" cmd=0 cmd_name="" celery=0 api_client=0 fe_dir="" ty_file=""
    local sn app_sn
    sn="$(_make_django_snake "$Name")"
    app_sn="$(_make_django_snake "$app")"
    if [ "$yes" = 1 ]; then
        # Non-interactive: scaffold the full stack by default.
        mgr=1; adm=1; ser=1; view=1; flt=1; url=1; perm=1
        etl=1; etl_lib="pandas"; sql_name="${sn}"; etl_fn="process_${sn}_query"
        cmd=1; cmd_name="${app_sn}"
        celery=1; api_client=1
        fe_dir="$(_make_django_frontend_dir "$root" "$app")"
        ty_file="$(_make_django_typings_file "$root" "$app")"
    else
        if _make_django_confirm "Create a Manager class for ${Name} (managers.py)? [Y/n]: "; then mgr=1; fi
        if _make_django_confirm "Register ${Name} in admin.py? [Y/n]: "; then adm=1; fi
        if _make_django_confirm "Create a DRF serializer (api/serializers.py)? [Y/n]: "; then ser=1; fi
        if _make_django_confirm "Create a DRF viewset (api/views.py)? [Y/n]: "; then view=1; fi
        if _make_django_confirm "Create a django-filter filterset (api/filters.py)? [Y/n]: "; then flt=1; fi
        if _make_django_confirm "Register the viewset in api/urls.py? [Y/n]: "; then url=1; fi
        if _make_django_confirm "Create a permission class (permissions.py)? [Y/n]: "; then perm=1; fi
        if _make_django_confirm "Is ETL expected for ${Name} (data_etl/ + SQL query)? [y/N]: "; then
            etl=1
            read -r -p "ETL processing library (pandas/polars) [pandas]: " etl_lib
            case "$etl_lib" in
                polars|pandas) ;;
                *) etl_lib="pandas" ;;
            esac
            read -r -p "SQL query file name [${sn}]: " sql_name
            sql_name="${sql_name:-${sn}}"
            read -r -p "Query processing function name [process_${sn}_query]: " etl_fn
            etl_fn="${etl_fn:-process_${sn}_query}"
        fi
        if [ "$etl" = 1 ] && _make_django_confirm "Create a management command to run the ETL ('manage.py ${app_sn}')? [y/N]: "; then
            cmd=1
            read -r -p "Management command name [${app_sn}]: " cmd_name
            cmd_name="${cmd_name:-${app_sn}}"
        fi
        if [ "$etl" = 1 ] && _make_django_confirm "Register a Celery worker task in developer_console/tasks.py? [y/N]: "; then celery=1; fi
        if _make_django_confirm "Create API client functions + TypeScript interfaces (frontend/typings/*.d.ts)? [y/N]: "; then
            api_client=1
            fe_dir="$(_make_django_frontend_dir "$root" "$app")"
            read -r -p "Frontend feature dir [${fe_dir}]: " fe_in
            fe_dir="${fe_in:-${fe_dir}}"
            ty_file="$(_make_django_typings_file "$root" "$app")"
        fi
    fi

    # --- permission source ------------------------------------------------------
    local perm_src="scaffold"
    if [ "$yes" != 1 ] && [ "$view" = 1 ] && [ -d "$root/shared_tools" ]; then
        echo "Note: 'shared_tools' was found — viewsets can use PERM_INTERNAL_COLLEAGUE directly."
        read -r -p "Permission source: shared_tools (s) or scaffold an app permission (a)? [a]: " ps
        case "$ps" in
            [sS]*) perm_src="shared_tools" ;;
        esac
    fi
    # If no permission class was requested, default to shared_tools when present.
    if [ "$view" = 1 ] && [ "$perm" = 0 ] && [ "$perm_src" = "scaffold" ] && [ -d "$root/shared_tools" ]; then
        perm_src="shared_tools"
    fi

    # --- summary + confirm -------------------------------------------------------
    echo ""
    echo "Model:      ${Name}"
    echo "App:        ${app}"
    echo "Fields:     ${arg_fields}"
    echo "Base:       ${base}"
    echo "Features:   manager=${mgr} admin=${adm} serializer=${ser} viewset=${view} filterset=${flt} urls=${url} permissions=${perm} (perms source: ${perm_src})"
    echo "ETL:        etl=${etl}${etl:+ lib=${etl_lib} sql=${sql_name} fn=${etl_fn}}"
    echo "Extras:     command=${cmd}${cmd:+ name=${cmd_name}} celery=${celery} api-client=${api_client}${api_client:+ dir=${fe_dir} typings=${ty_file}}"
    if [ "$yes" != 1 ]; then
        read -r -p "Scaffold ${Name} in app '${app}'? [y/N]: " yn
        case "$yn" in
            [yY]*) ;;
            *) echo "Cancelled."; return 1 ;;
        esac
    fi

    # --- run generator ------------------------------------------------------------
    "$py" "$DJANGO_SCAFFOLD_DIR/model_scaffold.py" \
        --root "$root" --app "$app" --name "$Name" --fields "$arg_fields" --base "$base" \
        --manager "$mgr" --admin "$adm" --serializer "$ser" --viewset "$view" \
        --filterset "$flt" --urls "$url" --permissions "$perm" \
        --permission-source "$perm_src" \
        --etl "$etl" --etl-lib "$etl_lib" --sql-name "$sql_name" --etl-function "$etl_fn" \
        --command "$cmd" --command-name "$cmd_name" \
        --celery "$celery" --api-client "$api_client" --frontend-dir "$fe_dir" --typings-file "$ty_file" || return 1

    echo ""
    if _make_django_confirm "Run 'python manage.py makemigrations ${app}' now? [y/N]: "; then
        (cd "$root" && "$py" manage.py makemigrations "$app")
    fi
}

_make_django_autocomplete() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "model help" -- "${cur}") )
    return 0
}
complete -F _make_django_autocomplete make-django
