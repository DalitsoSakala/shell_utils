#!/usr/bin/env bash
# Android Makefile Integration Helper
# Sourced in shell to expose the 'make-android' command.

ANDROID_REF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/android_ref.sh"

# -----------------------------------------------------------------------------
# make-android — Android project Makefile generator and execution wrapper
#
# Usage:
#   make-android init        Initialize Makefile in the current directory
#   make-android <target>    Run a target from the Makefile (e.g. build, dev, logs)
# -----------------------------------------------------------------------------

_make_android_print_help() {
    cat <<'EOF'
make-android — Android project Makefile generator, execution wrapper, and Jetpack Compose creator

Usage:
  make-android create [name] Initialize a new Jetpack Compose Android project in CLI
  make-android init         Initialize or update the Makefile in this directory
  make-android model [name] [fields] [--api-sync] Scaffold domain + data files for a new model
                          (--api-sync adds outbox sync; via make: make -- model Name --api-sync)
  make-android component    Scaffold a Jetpack Compose component (list/tabs/form)
  make-android wifi         Discover & connect to Android devices over Wi-Fi
  make-android <target>     Execute a target from the Makefile (e.g., build, dev, logs, stop)

Available Make Targets:
  build     Build the debug APK (./gradlew assembleDebug)
  install   Install the APK on connected device/emulator
  run       Launch the main activity
  dev       Combined step: build -> install -> run
  logs      Stream Logcat output for this app's process
  stop      Stop app process on device
  clean     Clean build artifacts
  help      Show this help message
EOF
}

make-android() {
    case "${1:-}" in
        -h|-help|--help)
            _make_android_print_help
            return 0
            ;;
    esac

    # Command dependencies check
    if ! command -v make >/dev/null 2>&1; then
        echo "Warning: 'make' is not installed or not in PATH." >&2
    fi

    # Subcommand: init
    if [ "${1:-}" = "init" ]; then
        _make_android_init
        return $?
    fi

    # Subcommand: create
    if [ "${1:-}" = "create" ]; then
        shift
        _make_android_create "$@"
        return $?
    fi

    # Subcommand: wifi
    if [ "${1:-}" = "wifi" ]; then
        _make_android_wifi
        return $?
    fi

    # Subcommand: model (optional name + fields args: make-android model Farmer name,age:Int)
    if [ "${1:-}" = "model" ]; then
        _make_android_model "${2:-}" "${3:-}"
        return $?
    fi

    # Subcommand: component
    if [ "${1:-}" = "component" ]; then
        _make_android_component
        return $?
    fi

    # For any other target, verify Makefile exists first
    if [ ! -f "Makefile" ]; then
        if [ "${1:-}" = "help" ]; then
            _make_android_print_help
            return 0
        fi
        echo "No Makefile found in the current directory."
        read -r -p "Would you like to initialize a Makefile for this Android project? [y/N]: " yn
        case "$yn" in
            [yY]* )
                _make_android_init || return 1
                ;;
            * )
                echo "Operation cancelled."
                return 1
                ;;
        esac
    fi

    # Run the make command with the specified targets
    make "$@"
}

_make_android_init() {
    # Verify we are in an Android project
    if [ ! -f "gradlew" ] && [ ! -f "build.gradle" ] && [ ! -f "build.gradle.kts" ] && [ ! -d "app" ]; then
        echo "Warning: Current directory does not look like an Android project root."
        read -r -p "Do you want to initialize here anyway? [y/N]: " yn
        case "$yn" in
            [yY]* ) ;;
            * ) return 1 ;;
        esac
    fi

    local pkg=""
    local activity=""
    local apk_path="app/build/outputs/apk/debug/app-debug.apk"

    echo "Scanning project for Android configuration..."

    # 1. Search for MainActivity source file to extract package and activity name
    local main_activity_file
    main_activity_file=$(find . -maxdepth 8 -type f \( -name "MainActivity.kt" -o -name "MainActivity.java" \) -not -path "*/build/*" 2>/dev/null | head -n 1)

    if [ -n "$main_activity_file" ]; then
        pkg=$(grep -m 1 "^[[:space:]]*package[[:space:]]" "$main_activity_file" | awk '{print $2}' | tr -d ';[:space:]')
        local base_name
        base_name=$(basename "$main_activity_file")
        activity=".${base_name%.*}"
        echo "Found main activity source: $main_activity_file"
    fi

    # 2. If package is still empty, scan Gradle files
    if [ -z "$pkg" ]; then
        pkg=$(grep -roE '(namespace|applicationId)[[:space:]]*(=)?[[:space:]]*["'\''].+["'\'']' . 2>/dev/null | head -n 1 | grep -oE '["'\''].+["'\'']' | tr -d '"'\''[:space:]')
    fi

    # 3. If package or activity is empty, scan AndroidManifest.xml files
    if [ -z "$pkg" ] || [ -z "$activity" ]; then
        local manifest_file
        manifest_file=$(find . -maxdepth 8 -type f -name "AndroidManifest.xml" -not -path "*/build/*" 2>/dev/null | head -n 1)
        if [ -n "$manifest_file" ]; then
            if [ -z "$pkg" ]; then
                pkg=$(grep -oE 'package="[^"]+"' "$manifest_file" | head -n 1 | cut -d'"' -f2 | tr -d '[:space:]')
            fi
            if [ -z "$activity" ]; then
                local manifest_act
                manifest_act=$(grep -oE 'android:name="[^"]*MainActivity[^"]*"' "$manifest_file" | head -n 1 | cut -d'"' -f2 | tr -d '[:space:]')
                if [ -n "$manifest_act" ]; then
                    activity="$manifest_act"
                fi
            fi
        fi
    fi

    # 4. Check for APK file to suggest apk path
    local detected_apk
    detected_apk=$(find . -maxdepth 6 -type f -name "*.apk" -not -path "*/build/intermediates/*" 2>/dev/null | head -n 1)
    if [ -n "$detected_apk" ]; then
        apk_path="${detected_apk#./}"
    fi

    # Prompt user for confirmation/customization
    echo "Please confirm or customize the Makefile configuration:"
    
    read -r -p "Package Name [${pkg:-com.example.cliapp}]: " input_pkg
    pkg="${input_pkg:-${pkg:-com.example.cliapp}}"

    read -r -p "Main Activity [${activity:-.MainActivity}]: " input_activity
    activity="${input_activity:-${activity:-.MainActivity}}"

    read -r -p "APK Path [${apk_path}]: " input_apk
    apk_path="${input_apk:-${apk_path}}"

    # Prompt for Neovim config integration
    read -r -p "Update/Sync Neovim config with Jetpack Compose snippets? [y/N]: " input_nvim_snip
    case "$input_nvim_snip" in
        [yY]*) _update_nvim_snippets ;;
        *) ;;
    esac

    # Confirm if Makefile exists
    if [ -f "Makefile" ]; then
        read -r -p "Makefile already exists in this directory. Overwrite? [y/N]: " yn
        case "$yn" in
            [yY]* ) ;;
            * ) echo "Cancelled."; return 1 ;;
        esac
    fi

    # Generate Makefile
    cat <<EOF > Makefile
# Makefile for Jetpack Compose CLI Workflow

PACKAGE_NAME = ${pkg}
MAIN_ACTIVITY = ${activity}
APK_PATH = ${apk_path}

.PHONY: all build install run clean logs dev stop help wifi preview model component

# Default action: Show help message
all: help

# 1. Build the debug APK
build:
	./gradlew assembleDebug

# 2. Install the APK on connected device/emulator
install:
	adb install -r \$(APK_PATH)

# 3. Launch the main activity
run:
	adb shell am start -n \$(PACKAGE_NAME)/\$(MAIN_ACTIVITY)

# 4. Generate Compose screenshot previews (can optionally specify FILE=...)
preview:
	@bash /home/dalitso/Projects/shell_utils/android/preview_scanner.sh \$(FILE)

# 5. Scaffold domain + data files for a new model (optional name arg: make model Farmer)
model:
	@bash -c 'source ${ANDROID_REF_PATH} && _make_android_model \$(foreach g,\$(filter-out \$@,\$(MAKECMDGOALS)),"\$g")'

# 6. Scaffold a Jetpack Compose component (list/tabs/form)
component:
	@bash -c 'source ${ANDROID_REF_PATH} && _make_android_component'

# Combined step: Build -> Install -> Run
dev: build install run

# Stream Logcat output for this app's process
logs:
	adb logcat --pid=\$\$(adb shell pidof -s \$(PACKAGE_NAME))

# Stop app process on device
stop:
	adb shell am force-stop \$(PACKAGE_NAME)

# Clean build artifacts
clean:
	./gradlew clean

# Discover and connect to available android devices over Wi-Fi
wifi:
	@if [ -f "${ANDROID_REF_PATH}" ]; then \\
		bash -c 'source ${ANDROID_REF_PATH} && _make_android_wifi'; \\
	else \\
		echo "This target requires the shell_utils android helper."; \\
		echo "Please connect manually."; \\
	fi

# Show this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build     Build the debug APK (./gradlew assembleDebug)"
	@echo "  install   Install the APK on connected device/emulator"
	@echo "  run       Launch the main activity"
	@echo "  preview   Generate Compose screenshot previews (FILE=SomeFile.kt)"
	@echo "  model     Scaffold domain + data files for a new model (make model <Name> [fields])"
	@echo "  component Scaffold a Jetpack Compose component (list/tabs/form)"
	@echo "  dev       Build, install, and run the app (default)"
	@echo "  logs      Stream Logcat output for the app"
	@echo "  stop      Stop app process on device"
	@echo "  clean     Clean build artifacts"
	@echo "  wifi      Discover and connect to devices over Wi-Fi"
	@echo "  help      Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make dev        Build, install, and launch the app"
	@echo "  make model Farmer name,age:Int    Scaffold a new domain/data model"
	@echo "  make component  Scaffold a new Compose component"
	@echo "  make preview FILE=SettingsScreen.kt   Generate a Compose preview"

# Catch-all: tolerate extra goals used as arguments (e.g. make model Farmer)
%:
	@:
EOF


    echo "Successfully generated Makefile!"
    if ! command -v adb >/dev/null 2>&1; then
        echo "Note: 'adb' is not currently in your PATH. You may need to install Android SDK platform-tools."
    fi
}

_make_android_wifi() {
    echo "============================================="
    echo "   Android WiFi Connection Assistant"
    echo "============================================="
    echo "1) Discover & Connect via mDNS (Android 11+)"
    echo "2) Pair new device via Pairing Code (Android 11+)"
    echo "3) Setup connection via USB first (Classic)"
    echo "q) Cancel"
    echo "============================================="
    read -r -p "Choose an option: " opt

    case "$opt" in
        1)
            echo "Scanning for wireless debugging services (mDNS)..."
            local services
            services=$(adb mdns services 2>/dev/null | grep -E '_adb-tls-connect|_adb' || true)
            if [ -z "$services" ]; then
                echo "No wireless devices found. Make sure Wireless Debugging is enabled."
                return 1
            fi

            local count=0
            local -a ips=()
            echo "Discovered Devices:"
            while read -r line; do
                if [ -n "$line" ] && [[ "$line" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+ ]]; then
                    count=$((count + 1))
                    local ip_port
                    ip_port=$(echo "$line" | awk '{print $1}')
                    ips+=("$ip_port")
                    echo "  $count) $ip_port"
                fi
            done <<< "$services"

            if [ "$count" -eq 0 ]; then
                echo "No valid IP:Port services discovered."
                return 1
            fi

            read -r -p "Select a device (1-$count) to connect: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                local selected_ip="${ips[$((choice - 1))]}"
                echo "Connecting to $selected_ip..."
                adb connect "$selected_ip"
            else
                echo "Invalid selection."
            fi
            ;;
        2)
            echo "On your Android device:"
            echo "  1. Go to Developer Options -> Wireless Debugging"
            echo "  2. Tap 'Pair device with pairing code'"
            echo ""
            read -r -p "Enter IP address and Port (e.g., 192.168.1.50:37859): " ip_port
            read -r -p "Enter 6-digit Pairing Code: " pair_code
            if [ -n "$ip_port" ] && [ -n "$pair_code" ]; then
                adb pair "$ip_port" "$pair_code"
                echo ""
                echo "Now, look at the main Wireless Debugging screen for the connection IP/Port."
                read -r -p "Enter IP address and connection Port (e.g., 192.168.1.50:41253): " connect_port
                if [ -n "$connect_port" ]; then
                    adb connect "$connect_port"
                fi
            else
                echo "IP/Port and Pairing Code are required."
            fi
            ;;
        3)
            echo "Checking for USB connected devices..."
            local usb_devices
            usb_devices=$(adb devices | grep -v "List of" | grep -v "adb" | grep "device" || true)
            if [ -z "$usb_devices" ]; then
                echo "No USB devices found. Please plug in your device via USB first."
                return 1
            fi

            echo "Detecting device IP address..."
            local ip_addr
            # Try getting via route (best for default interface ip)
            ip_addr=$(adb shell ip route get 1 2>/dev/null | awk '{print $7}' | tr -d '[:space:]')
            if [ -z "$ip_addr" ]; then
                # Fallback to scanning wlan0
                ip_addr=$(adb shell ip addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | tr -d '[:space:]')
            fi

            if [ -z "$ip_addr" ]; then
                echo "Could not auto-detect Wi-Fi IP address of the device."
                read -r -p "Please enter your device's Wi-Fi IP address (e.g., 192.168.1.50): " ip_addr
            fi

            if [ -n "$ip_addr" ]; then
                echo "Found device IP: $ip_addr"
                echo "Restarting adbd in TCP mode on port 5555..."
                adb tcpip 5555
                sleep 2
                echo "Connecting to $ip_addr:5555..."
                adb connect "$ip_addr:5555"
                echo "You can now unplug the USB cable!"
            else
                echo "IP address is required."
            fi
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
}

_make_android_init_silent() {
    # Generate Makefile without prompts
    cat <<EOF > Makefile
# Makefile for Jetpack Compose CLI Workflow

PACKAGE_NAME = ${pkg}
MAIN_ACTIVITY = ${activity}
APK_PATH = ${apk_path}

.PHONY: all build install run clean logs dev stop help wifi preview model component

# Default action: Show help message
all: help

# 1. Build the debug APK
build:
	./gradlew assembleDebug

# 2. Install the APK on connected device/emulator
install:
	adb install -r \$(APK_PATH)

# 3. Launch the main activity
run:
	adb shell am start -n \$(PACKAGE_NAME)/\$(MAIN_ACTIVITY)

# 4. Generate Compose screenshot previews (can optionally specify FILE=...)
preview:
	@bash /home/dalitso/Projects/shell_utils/android/preview_scanner.sh \$(FILE)

# 5. Scaffold domain + data files for a new model (optional name arg: make model Farmer)
model:
	@bash -c 'source ${ANDROID_REF_PATH} && _make_android_model \$(foreach g,\$(filter-out \$@,\$(MAKECMDGOALS)),"\$g")'

# 6. Scaffold a Jetpack Compose component (list/tabs/form)
component:
	@bash -c 'source ${ANDROID_REF_PATH} && _make_android_component'

# Combined step: Build -> Install -> Run
dev: build install run

# Stream Logcat output for this app's process
logs:
	adb logcat --pid=\$\$(adb shell pidof -s \$(PACKAGE_NAME))

# Stop app process on device
stop:
	adb shell am force-stop \$(PACKAGE_NAME)

# Clean build artifacts
clean:
	./gradlew clean

# Discover and connect to available android devices over Wi-Fi
wifi:
	@if [ -f "${ANDROID_REF_PATH}" ]; then \\
		bash -c 'source ${ANDROID_REF_PATH} && _make_android_wifi'; \\
	else \\
		echo "This target requires the shell_utils android helper."; \\
		echo "Please connect manually."; \\
	fi

# Show this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build     Build the debug APK (./gradlew assembleDebug)"
	@echo "  install   Install the APK on connected device/emulator"
	@echo "  run       Launch the main activity"
	@echo "  preview   Generate Compose screenshot previews (FILE=SomeFile.kt)"
	@echo "  model     Scaffold domain + data files for a new model (make model <Name> [fields])"
	@echo "  component Scaffold a Jetpack Compose component (list/tabs/form)"
	@echo "  dev       Build, install, and run the app (default)"
	@echo "  logs      Stream Logcat output for the app"
	@echo "  stop      Stop app process on device"
	@echo "  clean     Clean build artifacts"
	@echo "  wifi      Discover and connect to devices over Wi-Fi"
	@echo "  help      Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make dev        Build, install, and launch the app"
	@echo "  make model Farmer name,age:Int    Scaffold a new domain/data model"
	@echo "  make component  Scaffold a new Compose component"
	@echo "  make preview FILE=SettingsScreen.kt   Generate a Compose preview"

# Catch-all: tolerate extra goals used as arguments (e.g. make model Farmer)
%:
	@:
EOF

}

# -----------------------------------------------------------------------------
# make-android model — scaffold domain + data files for a new model
# -----------------------------------------------------------------------------

_make_android_pascal() {
    # "milk batch", "milk_batch", or "MilkBatch" -> "MilkBatch"
    echo "$1" | sed -E 's/[_ -]+/ /g' | awk '{
        for (i = 1; i <= NF; i++)
            printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2)
        print ""
    }'
}

_make_android_camel() {
    # "Name" -> "name", "PhoneNumber" -> "phoneNumber",
    # "full_name" -> "fullName", "phone-number" -> "phoneNumber", "tank id" -> "tankId"
    echo "$1" | sed -E 's/[_ -]+/ /g' | awk '{
        result = tolower(substr($1, 1, 1)) substr($1, 2)
        for (i = 2; i <= NF; i++)
            result = result toupper(substr($i, 1, 1)) substr($i, 2)
        print result
    }'
}

_make_android_type() {
    # Normalize a case-insensitive Kotlin type name to canonical casing.
    # "int"/"INT"/"Integer" -> "Int"; "boolean"/"Bool" -> "Boolean";
    # "localDateTime" -> "LocalDateTime"; empty -> "String"
    local t lower first
    t="$(echo "$1" | tr -d '[:space:]')"
    lower="$(echo "$t" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        string) echo "String" ;;
        int|integer) echo "Int" ;;
        long) echo "Long" ;;
        boolean|bool) echo "Boolean" ;;
        double) echo "Double" ;;
        float) echo "Float" ;;
        short) echo "Short" ;;
        byte) echo "Byte" ;;
        char) echo "Char" ;;
        *)
            if [ -z "$t" ]; then
                echo "String"
            else
                first="$(printf '%s' "${t:0:1}" | tr '[:lower:]' '[:upper:]')"
                echo "${first}${t:1}"
            fi
            ;;
    esac
}

_make_android_default() {
    # Default value literal for a canonical Kotlin type; empty means the
    # generated parameter is left without a default (required).
    case "$1" in
        String) echo '""' ;;
        Int|Short|Byte) echo "0" ;;
        Long) echo "0L" ;;
        Boolean) echo "false" ;;
        Double) echo "0.0" ;;
        Float) echo "0.0f" ;;
        Char) echo "' '" ;;
        *) echo "" ;;
    esac
}

_make_android_is_datetime() {
    # True when the type token is a datetime alias like '@datetime'/'@instant'
    # (with or without a leading '@', '&', or '#', case-insensitive). These resolve to
    # the project's canonical datetime class: java.time.Instant.
    case "$(echo "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in
        '@datetime'|'&datetime'|'#datetime'|'datetime'|'@instant'|'&instant'|'#instant'|'instant') return 0 ;;
        *) return 1 ;;
    esac
}

_make_android_snake() {
    # "MilkBatch" -> "milk_batch", "phoneNumber" -> "phone_number"
    echo "$1" \
        | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/[_ -]+/_/g' \
        | tr '[:upper:]' '[:lower:]'
}

_make_android_plural() {
    # "Farmer" -> "Farmers", "Batch" -> "Batches", "Category" -> "Categories",
    # "Status" -> "Statuses", "Analysis" -> "Analyses", "Shift" -> "Shifts"
    local s="$1"
    if [[ "$s" =~ [^aeiouAEIOU]y$ ]]; then
        echo "${s%y}ies"
    elif [[ "$s" =~ is$ ]]; then
        echo "${s%is}es"
    elif [[ "$s" =~ (s|x|z|ch|sh)$ ]]; then
        echo "${s}es"
    else
        echo "${s}s"
    fi
}

_make_android_detect_java_root() {
    # Prints the Kotlin/Java package source directory for the app module.
    local main_file pkg pkg_path root
    main_file=$(find . -maxdepth 8 -type f \( -name "MainActivity.kt" -o -name "MainActivity.java" \) -not -path "*/build/*" 2>/dev/null | head -n 1)
    if [ -n "$main_file" ]; then
        root="$(dirname "$main_file")"
        root="${root#./}"
        echo "$root"
        return 0
    fi
    pkg=$(grep -roE '(namespace|applicationId)[[:space:]]*(=)?[[:space:]]*["'\''].+["'\'']' . 2>/dev/null | head -n 1 | grep -oE '["'\''].+["'\'']' | tr -d '"'\''[:space:]')
    if [ -n "$pkg" ]; then
        pkg_path=$(echo "$pkg" | tr '.' '/')
        if [ -d "app/src/main/java/${pkg_path}" ]; then
            echo "app/src/main/java/${pkg_path}"
            return 0
        fi
    fi
    return 1
}

_make_android_sed_inplace() {
    # Portable in-place sed:  _make_android_sed_inplace 's/a/b/' file
    sed "$1" "$2" > "$2.tmp.$$" && mv "$2.tmp.$$" "$2"
}

_make_android_insert_before_last_brace() {
    # Insert 'text' (may contain newlines) right before the last top-level '}'.
    local file="$1" text="$2" last
    last=$(grep -n '^}' "$file" | tail -1 | cut -d: -f1)
    [ -z "$last" ] && return 1
    awk -v last="$last" -v txt="$text" 'NR==last {print txt} {print}' "$file" > "$file.tmp.$$" \
        && mv "$file.tmp.$$" "$file"
}

_make_android_insert_import() {
    # Insert 'import <pkg>' right after the last existing import (or package line).
    local file="$1" imp="import $2" anchor
    anchor=$(grep -n '^import ' "$file" | tail -1 | cut -d: -f1)
    if [ -z "$anchor" ]; then
        anchor=$(grep -n '^package ' "$file" | tail -1 | cut -d: -f1)
        [ -z "$anchor" ] && return 1
    fi
    awk -v anchor="$anchor" -v imp="$imp" '{print} NR==anchor {print imp}' "$file" > "$file.tmp.$$" \
        && mv "$file.tmp.$$" "$file"
}

_make_android_wire_database() {
    # Register {Name}Entity + {Name}Dao in AppDatabase, bump the Room version, and
    # scaffold data/local/AppDatabase.kt (with the entity registered) plus the
    # database-provider module when the database file does not exist yet.
    local java_root="$1" pkg="$2" Name="$3" name="$4"
    local db_file="${java_root}/data/local/AppDatabase.kt" ver accessor db_name
    local provider_file="${java_root}/di/DatabaseModule.kt"

    if [ ! -f "$db_file" ]; then
        mkdir -p "${java_root}/data/local"
        db_name="$(echo "$pkg" | awk -F. '{print $NF}').db"
        {
            cat <<EOF
package ${pkg}.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import ${pkg}.data.local.dao.${Name}Dao
import ${pkg}.data.local.entities.${Name}Entity

@Database(
    entities = [
        ${Name}Entity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun ${name}Dao(): ${Name}Dao
}
EOF
        } > "$db_file"
        echo "  - created ${db_file#${java_root}/} (registered ${Name}Entity + ${Name}Dao)."
    elif grep -q "${Name}Entity::class" "$db_file"; then
        echo "  - ${Name}Entity already registered in AppDatabase."
    else
        _make_android_sed_inplace "s/entities[[:space:]]*=[[:space:]]*\[/entities = [${Name}Entity::class, /" "$db_file"
        ver=$(grep -oE 'version[[:space:]]*=[[:space:]]*[0-9]+' "$db_file" | grep -oE '[0-9]+$' | head -1)
        if [ -n "$ver" ]; then
            local bump_yn
            read -r -p "  Increase AppDatabase version ($ver -> $((ver+1)))? [y/N]: " bump_yn
            case "$bump_yn" in
                [yY]* )
                    _make_android_sed_inplace "s/version[[:space:]]*=[[:space:]]*[0-9]\+/version = $((ver+1))/" "$db_file"
                    echo "  - bumped AppDatabase version to $((ver+1))."
                    ;;
                * )
                    echo "  - WARNING: schema changed (${Name}Entity added) but version left at $ver; Room may fail to open the database."
                    ;;
            esac
        fi
        accessor="    abstract fun ${name}Dao(): ${Name}Dao"
        grep -q "import ${pkg}.data.local.dao.${Name}Dao" "$db_file" \
            || _make_android_insert_import "$db_file" "${pkg}.data.local.dao.${Name}Dao"
        _make_android_insert_before_last_brace "$db_file" "$accessor"
        echo "  - registered ${Name}Entity + ${Name}Dao in ${db_file#${java_root}/}."
    fi

    if [ ! -f "$provider_file" ]; then
        mkdir -p "${java_root}/di"
        db_name="$(echo "$pkg" | awk -F. '{print $NF}').db"
        {
            cat <<EOF
package ${pkg}.di

import android.content.Context
import androidx.room.Room
import ${pkg}.data.local.AppDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "${db_name}"
        ).fallbackToDestructiveMigration().build()
    }
}
EOF
        } > "$provider_file"
        echo "  - created ${provider_file#${java_root}/} (provides AppDatabase)."
    fi
    return 0
}

_make_android_wire_di() {
    # Bind {Name}Repository -> {Name}RepositoryImpl in the @Binds Hilt module.
    local java_root="$1" pkg="$2" Name="$3" module bind
    module=$(grep -rl --include="*.kt" "@Binds" "${java_root}/di" 2>/dev/null | head -1)
    if [ -z "$module" ]; then
        echo "  - no @Binds module under di/; bind ${Name}Repository -> ${Name}RepositoryImpl manually."
        return 1
    fi
    if grep -q "bind${Name}Repository" "$module"; then
        echo "  - ${Name}Repository already bound in ${module#${java_root}/}."
    else
        grep -q "import ${pkg}.data.repository.${Name}RepositoryImpl" "$module" \
            || _make_android_insert_import "$module" "${pkg}.data.repository.${Name}RepositoryImpl"
        grep -q "import ${pkg}.domain.repository.${Name}Repository" "$module" \
            || _make_android_insert_import "$module" "${pkg}.domain.repository.${Name}Repository"
        printf -v bind '    @Binds\n    @Singleton\n    abstract fun bind%sRepository(impl: %sRepositoryImpl): %sRepository' "$Name" "$Name" "$Name"
        _make_android_insert_before_last_brace "$module" "$bind"
        echo "  - bound ${Name}Repository -> ${Name}RepositoryImpl in ${module#${java_root}/}."
    fi
    return 0
}

_make_android_wire_api() {
    # Point a Retrofit service at {Name}Dto: add GET/POST methods to an existing
    # Retrofit interface, or create a dedicated {Name}Api.kt when none exists.
    local java_root="$1" pkg="$2" Name="$3" Plural="$4" table="$5"
    local api methods
    api=$(grep -rlE --include="*.kt" "@(GET|POST|PUT|PATCH|DELETE)" "${java_root}/data/remote" 2>/dev/null | grep -v '/dto/' | head -1)
    if [ -z "$api" ]; then
        api="${java_root}/data/remote/${Name}Api.kt"
        {
            cat <<EOF
package ${pkg}.data.remote

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import ${pkg}.data.remote.dto.${Name}Dto

/** Retrofit service for ${Name} endpoints. */
interface ${Name}Api {
    @GET("${table}")
    suspend fun get${Plural}(): List<${Name}Dto>

    @POST("${table}")
    suspend fun create${Name}(@Body body: ${Name}Dto): ${Name}Dto
}
EOF
        } > "$api"
        echo "  - created ${api#${java_root}/} with GET/POST for ${Name}Dto."
        return 0
    fi
    if grep -q "${Name}Dto" "$api"; then
        echo "  - ${Name}Dto already referenced by ${api#${java_root}/}."
        return 0
    fi
    grep -q "import retrofit2.http.Body" "$api" || _make_android_insert_import "$api" "retrofit2.http.Body"
    grep -q "import retrofit2.http.GET" "$api" || _make_android_insert_import "$api" "retrofit2.http.GET"
    grep -q "import retrofit2.http.POST" "$api" || _make_android_insert_import "$api" "retrofit2.http.POST"
    grep -q "import ${pkg}.data.remote.dto.${Name}Dto" "$api" || _make_android_insert_import "$api" "${pkg}.data.remote.dto.${Name}Dto"
    printf -v methods '    @GET("%s")\n    suspend fun get%s(): List<%sDto>\n\n    @POST("%s")\n    suspend fun create%s(@Body body: %sDto): %sDto' \
        "$table" "$Plural" "$Name" "$table" "$Name" "$Name" "$Name"
    _make_android_insert_before_last_brace "$api" "$methods"
    echo "  - added GET/POST ${Name} methods to ${api#${java_root}/}."
    return 0
}

_make_android_ensure_sync_status() {
    # Create the shared SyncStatus enum + SyncableRepository interface when missing.
    local java_root="$1" pkg="$2"
    local file="${java_root}/domain/model/SyncStatus.kt"
    if [ -f "$file" ]; then
        : # already present
    else
        mkdir -p "${java_root}/domain/model"
        cat > "$file" <<EOF
package ${pkg}.domain.model

/** Local sync state for records waiting to be pushed to the API. */
enum class SyncStatus {
    /** New or edited locally, waiting to be pushed. */
    PENDING,
    /** Currently being pushed. */
    SYNCING,
    /** Successfully pushed; the server id is stored in serverId. */
    SYNCED,
    /** The last push attempt failed; it will be retried. */
    FAILED,
}
EOF
        echo "  create domain/model/SyncStatus.kt"
    fi

    local sync_file="${java_root}/domain/sync/SyncableRepository.kt"
    if [ ! -f "$sync_file" ]; then
        mkdir -p "${java_root}/domain/sync"
        cat > "$sync_file" <<EOF
package ${pkg}.domain.sync

/** Common contract for repositories that can push local records to the API (outbox). */
interface SyncableRepository<T> {
    /** Local records waiting to be pushed to the API (the outbox). */
    suspend fun getPendingSync(): List<T>
    /** Marks a record as synced and stores the server-assigned id. */
    suspend fun markSynced(id: Long, serverId: Long)
    /** Marks a failed push; the record stays in the outbox for retry. */
    suspend fun markFailed(id: Long)
    /** Pushes a record to the API. Returns the server-synced record on success. */
    suspend fun push(item: T): Result<T>
}
EOF
        echo "  create domain/sync/SyncableRepository.kt"
    fi
}

_make_android_model() {
    local arg api_sync=0
    local -a positional=()
    for arg in "$@"; do
        case "$arg" in
            --api-sync) api_sync=1 ;;
            *) positional+=("$arg") ;;
        esac
    done
    local arg_name="${positional[0]:-}"
    local arg_fields="${positional[1]:-}"
    if [ ! -d "app" ]; then
        echo "Error: run this from the Android project root (no 'app' directory found)." >&2
        return 1
    fi

    local java_root pkg
    java_root="$(_make_android_detect_java_root)"
    if [ -z "$java_root" ]; then
        echo "Error: could not detect the app package/source directory." >&2
        return 1
    fi
    pkg="${java_root#app/src/main/java/}"
    pkg="${pkg//\//.}"

    # 1. Model name (optional: _make_android_model "ModelName")
    local input_name="${arg_name}"
    if [ -z "$input_name" ]; then
        read -r -p "Model name (e.g. Region): " input_name
        input_name="${input_name:-}"
    fi
    if [ -z "$input_name" ]; then
        echo "Error: model name is required." >&2
        return 1
    fi

    local Name name Plural
    Name="$(_make_android_pascal "$input_name")"
    name="$(_make_android_camel "$Name")"
    Plural="$(_make_android_plural "$Name")"

    local sync_supertype=""
    if [ "$api_sync" = 1 ]; then
        sync_supertype=" : SyncableRepository<${Name}>"
    fi

    # Sync metadata (outbox): clientId/serverId/syncStatus only with --api-sync.
    if [ "$api_sync" = 1 ]; then
        _make_android_ensure_sync_status "$java_root" "$pkg"
    fi

    # 2. Room database table name (default: snake_case of the model name)
    local table_default table
    table_default="$(_make_android_snake "$Name")"
    read -r -p "Room database table name [${table_default}]: " input_table
    table="${input_table:-${table_default}}"

    # 3. Field names besides id (default: name; comma/space separated).
    #    Optional per-field Kotlin type: 'name' or 'age:Int', 'age:INT' (case-insensitive).
    #    Datetime alias: 'visited_at:@datetime' -> java.time.Instant (stored as ISO-8601 String).
    #    May be passed as the second arg: make model Farmer name,age:Int
    local input_fields="${arg_fields}"
    if [ -z "$input_fields" ]; then
        read -r -p "Field names besides id, e.g. 'name', 'age:Int', 'visited_at:@datetime' (comma-separated) [name]: " input_fields
        input_fields="${input_fields:-name}"
    fi

    local -a fields=() props=() columns=() types=() dflags=() display=()
    read -r -a fields <<< "${input_fields//,/ }"
    local f prop col ftype name_part type_part def dflag
    for f in "${fields[@]}"; do
        [ -z "$f" ] && continue
        name_part="$f"
        type_part=""
        if [[ "$f" == *:* ]]; then
            name_part="${f%%:*}"
            type_part="${f#*:}"
        fi
        prop="$(_make_android_camel "$name_part")"
        col="$(_make_android_snake "$prop")"
        dflag=0
        if [ -n "$type_part" ] && _make_android_is_datetime "$type_part"; then
            ftype="Instant"
            dflag=1
        elif [ -n "$type_part" ]; then
            ftype="$(_make_android_type "$type_part")"
        else
            ftype="String"
        fi
        props+=("$prop")
        columns+=("$col")
        types+=("$ftype")
        dflags+=("$dflag")
        display+=("${prop}:${ftype}")
    done
    if [ ${#props[@]} -eq 0 ]; then
        echo "Error: at least one field is required." >&2
        return 1
    fi

    echo ""
    echo "Model:   ${Name}"
    echo "Table:   ${table}"
    echo "Fields:  ${display[*]}"
    echo "Source:  ${java_root}"
    echo ""
    read -r -p "Scaffold domain + data files for this model? [y/N]: " yn
    case "$yn" in
        [yY]* ) ;;
        * ) echo "Cancelled."; return 1 ;;
    esac

    local overwrite=1
    if [ -f "${java_root}/domain/model/${Name}.kt" ] ||
       [ -f "${java_root}/domain/repository/${Name}Repository.kt" ] ||
       [ -f "${java_root}/data/local/entities/${Name}Entity.kt" ] ||
       [ -f "${java_root}/data/local/dao/${Name}Dao.kt" ] ||
       [ -f "${java_root}/data/repository/${Name}RepositoryImpl.kt" ] ||
       [ -f "${java_root}/data/remote/dto/${Name}Dto.kt" ]; then
        read -r -p "Some files for '${Name}' already exist. Overwrite them? [y/N]: " ow
        case "$ow" in
            [yY]* ) overwrite=1 ;;
            * ) overwrite=0 ;;
        esac
    fi

    # domain/model/{Model}.kt
    mkdir -p "${java_root}/domain/model"
    if [ -f "${java_root}/domain/model/${Name}.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/domain/model/${Name}.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/domain/model/${Name}.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.domain.model

import java.time.Instant

data class ${Name}(
    val id: Long = 0,
EOF
            for i in "${!props[@]}"; do
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    val %s: Instant = Instant.EPOCH,\n' "${props[$i]}"
                    continue
                fi
                def="$(_make_android_default "${types[$i]}")"
                if [ -n "$def" ]; then
                    printf '    val %s: %s = %s,\n' "${props[$i]}" "${types[$i]}" "$def"
                else
                    printf '    val %s: %s,\n' "${props[$i]}" "${types[$i]}"
                fi
            done
            printf '    val createdAt: Instant = Instant.EPOCH,\n'
            printf '    val updatedAt: Instant = Instant.EPOCH,\n'
            printf '    val createdBy: String = "",\n'
            if [ "$api_sync" = 1 ]; then
                printf '    val clientId: String = "",\n'
                printf '    val serverId: Long? = null,\n'
                printf '    val syncStatus: SyncStatus = SyncStatus.PENDING,\n'
            fi
            printf ')\n'
        } > "${java_root}/domain/model/${Name}.kt"
        echo "  ${action} ${java_root}/domain/model/${Name}.kt"
    fi

    # domain/repository/{Model}Repository.kt
    mkdir -p "${java_root}/domain/repository"
    if [ -f "${java_root}/domain/repository/${Name}Repository.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/domain/repository/${Name}Repository.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/domain/repository/${Name}Repository.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.domain.repository

import ${pkg}.domain.model.${Name}
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
import ${pkg}.domain.sync.SyncableRepository
EOF
            fi
            cat <<EOF
import kotlinx.coroutines.flow.Flow

interface ${Name}Repository${sync_supertype} {
    fun getAll${Plural}(): Flow<List<${Name}>>
    suspend fun get${Name}ById(id: Long): ${Name}?
    suspend fun upsert${Name}(item: ${Name})
    suspend fun delete${Name}(id: Long)
}
EOF
        } > "${java_root}/domain/repository/${Name}Repository.kt"
        echo "  ${action} ${java_root}/domain/repository/${Name}Repository.kt"
    fi

    # data/local/entities/{Model}Entity.kt
    mkdir -p "${java_root}/data/local/entities"
    if [ -f "${java_root}/data/local/entities/${Name}Entity.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/data/local/entities/${Name}Entity.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/data/local/entities/${Name}Entity.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.data.local.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "${table}")
data class ${Name}Entity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,
EOF
            for i in "${!props[@]}"; do
                printf '    @ColumnInfo(name = "%s")\n' "${columns[$i]}"
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    val %s: String = "",\n' "${props[$i]}"
                elif def="$(_make_android_default "${types[$i]}")" && [ -n "$def" ]; then
                    printf '    val %s: %s = %s,\n' "${props[$i]}" "${types[$i]}" "$def"
                else
                    printf '    val %s: %s,\n' "${props[$i]}" "${types[$i]}"
                fi
            done
            printf '    @ColumnInfo(name = "created_at")\n'
            printf '    val createdAt: String = "",\n'
            printf '    @ColumnInfo(name = "updated_at")\n'
            printf '    val updatedAt: String = "",\n'
            printf '    @ColumnInfo(name = "created_by")\n'
            printf '    val createdBy: String = "",\n'
            if [ "$api_sync" = 1 ]; then
                printf '    @ColumnInfo(name = "client_id")\n'
                printf '    val clientId: String = "",\n'
                printf '    @ColumnInfo(name = "server_id")\n'
                printf '    val serverId: Long? = null,\n'
                printf '    @ColumnInfo(name = "sync_status")\n'
                printf '    val syncStatus: String = "PENDING",\n'
            fi
            printf ')\n'
        } > "${java_root}/data/local/entities/${Name}Entity.kt"
        echo "  ${action} ${java_root}/data/local/entities/${Name}Entity.kt"
    fi

    # data/local/dao/{Model}Dao.kt
    mkdir -p "${java_root}/data/local/dao"
    if [ -f "${java_root}/data/local/dao/${Name}Dao.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/data/local/dao/${Name}Dao.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/data/local/dao/${Name}Dao.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import ${pkg}.data.local.entities.${Name}Entity
import kotlinx.coroutines.flow.Flow

@Dao
interface ${Name}Dao {
    /** Emits the full collection, ordered by id, on every change. */
    @Query("SELECT * FROM ${table} ORDER BY id")
    fun observeAll(): Flow<List<${Name}Entity>>

    /** Emits the item with the given id (or null) on every change. */
    @Query("SELECT * FROM ${table} WHERE id = :id")
    fun getById(id: Long): Flow<${Name}Entity?>

    /** Inserts or replaces a single item. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ${Name}Entity)

    /** Inserts or replaces a batch of items. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<${Name}Entity>)

    /** Deletes the item with the given id. */
    @Query("DELETE FROM ${table} WHERE id = :id")
    suspend fun deleteById(id: Long)
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF

    /** Returns records that still need to be pushed to the API (the outbox). */
    @Query("SELECT * FROM ${table} WHERE sync_status != 'SYNCED' ORDER BY id")
    fun getPendingSync(): List<${Name}Entity>

    /** Marks a record as synced and stores the server-assigned id. */
    @Query("UPDATE ${table} SET sync_status = 'SYNCED', server_id = :serverId WHERE id = :id")
    suspend fun markSynced(id: Long, serverId: Long)

    /** Records a failed push attempt; the record stays in the outbox for retry. */
    @Query("UPDATE ${table} SET sync_status = :status WHERE id = :id")
    suspend fun updateSyncStatus(id: Long, status: String)
EOF
            fi
            cat <<EOF
}
EOF
        } > "${java_root}/data/local/dao/${Name}Dao.kt"
        echo "  ${action} ${java_root}/data/local/dao/${Name}Dao.kt"
    fi

    # data/repository/{Model}RepositoryImpl.kt
    mkdir -p "${java_root}/data/repository"
    if [ -f "${java_root}/data/repository/${Name}RepositoryImpl.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/data/repository/${Name}RepositoryImpl.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/data/repository/${Name}RepositoryImpl.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.data.repository

import ${pkg}.data.local.AppDatabase
import ${pkg}.data.local.dao.${Name}Dao
import ${pkg}.data.local.entities.${Name}Entity
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
import ${pkg}.data.remote.AllegrowApi
import ${pkg}.data.remote.dto.toDomain
import ${pkg}.data.remote.dto.toDto
import ${pkg}.domain.model.SyncStatus
EOF
            fi
            cat <<EOF
import ${pkg}.domain.model.${Name}
import ${pkg}.domain.repository.${Name}Repository
import java.time.Instant
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
import java.util.UUID
EOF
            fi
            cat <<EOF
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class ${Name}RepositoryImpl @Inject constructor(
    private val db: AppDatabase,
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
    private val api: AllegrowApi,
EOF
            fi
            cat <<EOF
) : ${Name}Repository {

    private val ${name}Dao: ${Name}Dao = db.${name}Dao()

    override fun getAll${Plural}(): Flow<List<${Name}>> =
        ${name}Dao.observeAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun get${Name}ById(id: Long): ${Name}? =
        ${name}Dao.getById(id).first()?.toDomain()

    override suspend fun upsert${Name}(item: ${Name}) {
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
        val entity = item.toEntity().copy(clientId = item.clientId.ifBlank { UUID.randomUUID().toString() })
        ${name}Dao.upsert(entity)
EOF
            else
                cat <<EOF
        ${name}Dao.upsert(item.toEntity())
EOF
            fi
            cat <<EOF
    }

    override suspend fun delete${Name}(id: Long) {
        ${name}Dao.deleteById(id)
    }
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF

    override suspend fun getPendingSync(): List<${Name}> =
        ${name}Dao.getPendingSync().map { it.toDomain() }

    override suspend fun markSynced(id: Long, serverId: Long) {
        ${name}Dao.markSynced(id, serverId)
    }

    override suspend fun markFailed(id: Long) {
        ${name}Dao.updateSyncStatus(id, "FAILED")
    }

    override suspend fun push(item: ${Name}): Result<${Name}> = try {
        Result.success(api.create${Name}(item.toDto()).toDomain())
    } catch (e: Exception) {
        Result.failure(e)
    }
EOF
            fi
            cat <<EOF
}

/** Maps a Room entity to the domain model. */
fun ${Name}Entity.toDomain(): ${Name} = ${Name}(
    id = id,
EOF
            for i in "${!props[@]}"; do
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    %s = %s.toInstantOrEpoch(),\n' "${props[$i]}" "${props[$i]}"
                else
                    printf '    %s = %s,\n' "${props[$i]}" "${props[$i]}"
                fi
            done
            printf '    createdAt = createdAt.toInstantOrEpoch(),\n'
            printf '    updatedAt = updatedAt.toInstantOrEpoch(),\n'
            printf '    createdBy = createdBy,\n'
            if [ "$api_sync" = 1 ]; then
                printf '    clientId = clientId,\n'
                printf '    serverId = serverId,\n'
                printf '    syncStatus = SyncStatus.valueOf(syncStatus),\n'
            fi
            printf ')\n\n'
            cat <<EOF
/** Maps a domain model to a Room entity (for local writes). */
fun ${Name}.toEntity(): ${Name}Entity = ${Name}Entity(
    id = id,
EOF
            for i in "${!props[@]}"; do
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    %s = %s.toString(),\n' "${props[$i]}" "${props[$i]}"
                else
                    printf '    %s = %s,\n' "${props[$i]}" "${props[$i]}"
                fi
            done
            printf '    createdAt = createdAt.toString(),\n'
            printf '    updatedAt = updatedAt.toString(),\n'
            printf '    createdBy = createdBy,\n'
            if [ "$api_sync" = 1 ]; then
                printf '    clientId = clientId,\n'
                printf '    serverId = serverId,\n'
                printf '    syncStatus = syncStatus.name,\n'
            fi
            printf ')\n'
            cat <<EOF

/** Parses an ISO-8601 string to an Instant, defaulting to the epoch when blank. */
private fun String.toInstantOrEpoch(): Instant =
    if (isBlank()) Instant.EPOCH else Instant.parse(this)
EOF
        } > "${java_root}/data/repository/${Name}RepositoryImpl.kt"
        echo "  ${action} ${java_root}/data/repository/${Name}RepositoryImpl.kt"
    fi

    # data/remote/dto/{Model}Dto.kt (snake_case JSON keys)
    mkdir -p "${java_root}/data/remote/dto"
    if [ -f "${java_root}/data/remote/dto/${Name}Dto.kt" ] && [ "$overwrite" = 0 ]; then
        echo "  skip   ${java_root}/data/remote/dto/${Name}Dto.kt (already exists)"
    else
        local action="create"
        [ -f "${java_root}/data/remote/dto/${Name}Dto.kt" ] && action="overwrite"
        {
            cat <<EOF
package ${pkg}.data.remote.dto

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import ${pkg}.domain.model.${Name}
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
import ${pkg}.domain.model.SyncStatus
EOF
            fi
            cat <<EOF
import java.time.Instant

@JsonClass(generateAdapter = true)
data class ${Name}Dto(
    @Json(name = "id")
    val id: Long = 0,
EOF
            for i in "${!props[@]}"; do
                printf '    @Json(name = "%s")\n' "${columns[$i]}"
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    val %s: String = "",\n' "${props[$i]}"
                elif def="$(_make_android_default "${types[$i]}")" && [ -n "$def" ]; then
                    printf '    val %s: %s = %s,\n' "${props[$i]}" "${types[$i]}" "$def"
                else
                    printf '    val %s: %s,\n' "${props[$i]}" "${types[$i]}"
                fi
            done
            cat <<EOF
    @Json(name = "created_at")
    val createdAt: String = "",
    @Json(name = "updated_at")
    val updatedAt: String = "",
    @Json(name = "created_by")
    val createdBy: String = "",
EOF
            if [ "$api_sync" = 1 ]; then
                cat <<EOF
    @Json(name = "client_id")
    val clientId: String = "",
    @Json(name = "server_id")
    val serverId: Long? = null,
    @Json(name = "sync_status")
    val syncStatus: String = "PENDING",
EOF
            fi
            cat <<EOF
)

/** Maps a domain model to the API DTO (snake_case JSON keys). */
fun ${Name}.toDto(): ${Name}Dto = ${Name}Dto(
    id = id,
EOF
            for i in "${!props[@]}"; do
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    %s = %s.toString(),\n' "${props[$i]}" "${props[$i]}"
                else
                    printf '    %s = %s,\n' "${props[$i]}" "${props[$i]}"
                fi
            done
            printf '    createdAt = createdAt.toString(),\n'
            printf '    updatedAt = updatedAt.toString(),\n'
            printf '    createdBy = createdBy,\n'
            if [ "$api_sync" = 1 ]; then
                printf '    clientId = clientId,\n'
                printf '    serverId = serverId,\n'
                printf '    syncStatus = syncStatus.name,\n'
            fi
            cat <<EOF
)

/** Maps an API DTO to the domain model. */
fun ${Name}Dto.toDomain(): ${Name} = ${Name}(
    id = id,
EOF
            for i in "${!props[@]}"; do
                if [ "${dflags[$i]}" = 1 ]; then
                    printf '    %s = %s.toInstantOrEpoch(),\n' "${props[$i]}" "${props[$i]}"
                else
                    printf '    %s = %s,\n' "${props[$i]}" "${props[$i]}"
                fi
            done
            printf '    createdAt = createdAt.toInstantOrEpoch(),\n'
            printf '    updatedAt = updatedAt.toInstantOrEpoch(),\n'
            printf '    createdBy = createdBy,\n'
            if [ "$api_sync" = 1 ]; then
                printf '    clientId = clientId,\n'
                printf '    serverId = serverId,\n'
                printf '    syncStatus = SyncStatus.valueOf(syncStatus),\n'
            fi
            printf ')\n'
            cat <<EOF

/** Parses an ISO-8601 string to an Instant, defaulting to the epoch when blank. */
private fun String.toInstantOrEpoch(): Instant =
    if (isBlank()) Instant.EPOCH else Instant.parse(this)
EOF
        } > "${java_root}/data/remote/dto/${Name}Dto.kt"
        echo "  ${action} ${java_root}/data/remote/dto/${Name}Dto.kt"
    fi

    echo ""
    if [ "$api_sync" = 1 ]; then
        echo "Scaffolded ${Name} (table '${table}') with API-sync outbox metadata."
    else
        echo "Scaffolded ${Name} (table '${table}')."
    fi

    local wired_db="manual" wired_di="manual" wired_api="manual" yn
    read -r -p "Register ${Name}Entity + ${Name}Dao in AppDatabase? [y/N]: " yn
    case "$yn" in
        [yY]* ) _make_android_wire_database "$java_root" "$pkg" "$Name" "$name" && wired_db="done" ;;
    esac
    read -r -p "Bind ${Name}Repository -> ${Name}RepositoryImpl in DI? [y/N]: " yn
    case "$yn" in
        [yY]* ) _make_android_wire_di "$java_root" "$pkg" "$Name" && wired_di="done" ;;
    esac
    read -r -p "Point a Retrofit service at ${Name}Dto? [y/N]: " yn
    case "$yn" in
        [yY]* ) _make_android_wire_api "$java_root" "$pkg" "$Name" "$Plural" "$table" && wired_api="done" ;;
    esac

    echo ""
    echo "Next steps:"
    echo "  - [${wired_db}]   register ${Name}Entity and ${Name}Dao in AppDatabase"
    echo "  - [${wired_di}]   bind ${Name}Repository -> ${Name}RepositoryImpl in the DI module"
    echo "  - [${wired_api}]  point a Retrofit service at ${Name}Dto (snake_case JSON keys)"
    if [ "$api_sync" = 1 ]; then
        echo "  - [sync]   outbox methods scaffolded (getPendingSync/markSynced/markFailed/push)"
    fi
}

# -----------------------------------------------------------------------------
# make-android component — scaffold a Jetpack Compose component (ui/screens)
# -----------------------------------------------------------------------------

_make_android_component() {
    if [ ! -d "app" ]; then
        echo "Error: run this from the Android project root (no 'app' directory found)." >&2
        return 1
    fi

    local java_root pkg
    java_root="$(_make_android_detect_java_root)"
    if [ -z "$java_root" ]; then
        echo "Error: could not detect the app package/source directory." >&2
        return 1
    fi
    pkg="${java_root#app/src/main/java/}"
    pkg="${pkg//\//.}"

    # 1. Component type
    echo "Choose a Compose component type:"
    echo "  1) Generic composable list view"
    echo "  2) Generic scrollable tab view"
    echo "  3) Generic composable form"
    read -r -p "Type [1]: " input_type
    input_type="${input_type:-1}"
    local ctype
    case "$input_type" in
        1|list|listview|list_view) ctype="list" ;;
        2|tab|tabs|tabview|tab_view) ctype="tabs" ;;
        3|form) ctype="form" ;;
        *)
            echo "Invalid choice: $input_type" >&2
            return 1
            ;;
    esac

    # 2. Component name
    read -r -p "Component name (e.g. ProductList): " input_name
    input_name="${input_name:-}"
    if [ -z "$input_name" ]; then
        echo "Error: component name is required." >&2
        return 1
    fi
    local Name
    Name="$(_make_android_pascal "$input_name")"

    local dir="${java_root}/ui/screens"
    local file="${dir}/${Name}.kt"

    echo ""
    echo "Type:     ${ctype}"
    echo "Name:     ${Name}"
    echo "Package:  ${pkg}.ui.screens"
    echo "File:     ${file}"
    echo ""
    read -r -p "Create this Compose component? [y/N]: " yn
    case "$yn" in
        [yY]* ) ;;
        * ) echo "Cancelled."; return 1 ;;
    esac

    if [ -f "$file" ]; then
        read -r -p "'${file}' already exists. Overwrite? [y/N]: " ow
        case "$ow" in
            [yY]* ) ;;
            * ) echo "Cancelled."; return 1 ;;
        esac
    fi

    mkdir -p "$dir"

    case "$ctype" in
        list)
            cat <<EOF > "$file"
package ${pkg}.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Generic scrollable list view for [T].
 *
 * Renders [items] with [itemContent]; switch the source to a
 * Flow + collectAsState() when wiring up a repository.
 */
@Composable
fun <T> ${Name}(
    items: List<T>,
    modifier: Modifier = Modifier,
    itemContent: @Composable (T) -> Unit = {},
) {
    Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items) { item -> itemContent(item) }
        }
    }
}

/** Preview of the list view with sample data. */
@Preview(showBackground = true)
@Composable
private fun ${Name}Preview() {
    MaterialTheme {
        ${Name}(
            items = listOf("Item 1", "Item 2", "Item 3"),
            itemContent = { item -> Text(text = item) },
        )
    }
}
EOF
            ;;

        tabs)
            cat <<EOF > "$file"
package ${pkg}.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Generic scrollable tab view.
 *
 * Renders [tabTitles] in a horizontally scrollable [ScrollableTabRow] and
 * delegates the active page to [tabContent].
 */
@Composable
fun ${Name}(
    tabTitles: List<String>,
    modifier: Modifier = Modifier,
    tabContent: @Composable (index: Int) -> Unit = {},
) {
    var selectedTab by rememberSaveable { mutableStateOf(0) }

    Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            ScrollableTabRow(
                selectedTabIndex = selectedTab,
                edgePadding = 16.dp,
            ) {
                tabTitles.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(text = title) },
                    )
                }
            }
            tabContent(selectedTab)
        }
    }
}

/** Preview of the scrollable tab view with sample data. */
@Preview(showBackground = true)
@Composable
private fun ${Name}Preview() {
    MaterialTheme {
        ${Name}(
            tabTitles = listOf("Tab 1", "Tab 2", "Tab 3"),
            tabContent = { index -> Text(text = "Content for tab \$index") },
        )
    }
}
EOF
            ;;

        form)
            cat <<EOF > "$file"
package ${pkg}.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Generic composable form.
 *
 * Renders one [OutlinedTextField] per (label, initial value) pair and
 * reports the collected values via [onSave].
 */
@Composable
fun ${Name}(
    fields: List<Pair<String, String>> = listOf("Name" to ""),
    onSave: (List<String>) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var values by rememberSaveable { mutableStateOf(fields.map { it.second }) }

    Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            fields.forEachIndexed { index, (label, _) ->
                OutlinedTextField(
                    value = values.getOrElse(index) { "" },
                    onValueChange = { newValue ->
                        values = values.toMutableList().apply {
                            while (size <= index) add("")
                            set(index, newValue)
                        }
                    },
                    label = { Text(text = label) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Button(
                onClick = { onSave(values) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(text = "Save")
            }
        }
    }
}

/** Preview of the form with sample fields. */
@Preview(showBackground = true)
@Composable
private fun ${Name}Preview() {
    MaterialTheme {
        ${Name}(
            fields = listOf("Name" to "Jane", "Phone" to ""),
            onSave = {},
        )
    }
}
EOF
            ;;
    esac

    echo "  create ${file}"
    echo ""
    echo "Created Compose component ${Name} in ui/screens."
}

_make_android_create() {
    local proj_name="${1:-}"
    if [ -z "$proj_name" ]; then
        read -r -p "Enter Project Name (e.g., my-compose-app): " proj_name
    fi

    if [ -z "$proj_name" ]; then
        echo "Error: Project name is required." >&2
        return 1
    fi

    # Normalize project name for package name (alphanumeric, lowercase)
    local pkg_suffix
    pkg_suffix=$(echo "$proj_name" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    local default_pkg="com.example.${pkg_suffix}"

    read -r -p "Enter Package Name [${default_pkg}]: " pkg
    pkg="${pkg:-${default_pkg}}"

    local target_dir="./${proj_name}"
    read -r -p "Enter Target Directory [${target_dir}]: " input_dir
    target_dir="${input_dir:-${target_dir}}"

    if [ -d "$target_dir" ]; then
        read -r -p "Directory '${target_dir}' already exists. Overwrite contents? [y/N]: " yn
        case "$yn" in
            [yY]* ) ;;
            * ) echo "Cancelled."; return 1 ;;
        esac
    fi

    echo "Scaffolding Jetpack Compose project at ${target_dir}..."
    local pkg_path
    pkg_path=$(echo "$pkg" | tr '.' '/')
    
    mkdir -p "${target_dir}/app/src/main/java/${pkg_path}"
    mkdir -p "${target_dir}/app/src/main/res"
    mkdir -p "${target_dir}/gradle/wrapper"

    # 1. Project level settings.gradle.kts
    cat <<EOF > "${target_dir}/settings.gradle.kts"
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "${proj_name}"
include(":app")
EOF

    # 2. Project level build.gradle.kts
    cat <<EOF > "${target_dir}/build.gradle.kts"
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

    # 3. App level build.gradle.kts
    cat <<EOF > "${target_dir}/app/build.gradle.kts"
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "${pkg}"
    compileSdk = 34

    defaultConfig {
        applicationId = "${pkg}"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
}
EOF

    # 4. Proguard rules
    touch "${target_dir}/app/proguard-rules.pro"

    # 5. AndroidManifest.xml
    cat <<EOF > "${target_dir}/app/src/main/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@android:drawable/sym_def_app_icon"
        android:label="${proj_name}"
        android:roundIcon="@android:drawable/sym_def_app_icon"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.Material.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:label="${proj_name}"
            android:theme="@android:style/Theme.Material.NoActionBar">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

    # 6. MainActivity.kt
    local main_act_path="${target_dir}/app/src/main/java/${pkg_path}/MainActivity.kt"
    cat <<EOF > "$main_act_path"
package ${pkg}

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    Greeting("Jetpack Compose CLI")
                }
            }
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello \$name!",
        modifier = modifier.padding(16.dp),
        style = MaterialTheme.typography.headlineMedium
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    MaterialTheme {
        Greeting("Android")
    }
}
EOF

    # 7. Setup Gradle Wrapper
    if command -v gradle >/dev/null 2>&1; then
        echo "Generating Gradle wrapper locally..."
        (cd "$target_dir" && gradle wrapper --gradle-version 8.5)
    else
        echo "Gradle is not installed on system path. Fetching Gradle wrapper v8.5..."
        curl -sL -o "${target_dir}/gradle/wrapper/gradle-wrapper.jar" "https://github.com/gradle/gradle/raw/v8.5.0/gradle/wrapper/gradle-wrapper.jar"
        curl -sL -o "${target_dir}/gradlew" "https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradlew"
        chmod +x "${target_dir}/gradlew"
        curl -sL -o "${target_dir}/gradlew.bat" "https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradlew.bat"
        
        cat <<EOF > "${target_dir}/gradle/wrapper/gradle-wrapper.properties"
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
networkTimeout=10000
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
    fi

    # 8. Create the Makefile automatically in the new project!
    echo "Creating Makefile integration..."
    (
        cd "$target_dir"
        local pkg="$pkg"
        local activity=".MainActivity"
        local apk_path="app/build/outputs/apk/debug/app-debug.apk"
        _make_android_init_silent
    )

    echo "=========================================================="
    echo " Successfully created Jetpack Compose project: ${proj_name}"
    echo " Location: ${target_dir}"
    echo "=========================================================="
    echo " To get started:"
    echo "   cd ${target_dir}"
    echo "   make          # Shows available workflow targets"
    echo "   make dev      # Builds, installs, and runs the app"
    echo "=========================================================="
}

_update_nvim_snippets() {
    local snippets_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nvim/snippets"
    mkdir -p "$snippets_dir"
    
    echo "Updating Neovim snippets in ${snippets_dir}..."
    
    # Generate package.json
    cat <<'EOF' > "${snippets_dir}/package.json"
{
  "name": "custom-snippets",
  "engines": {
    "vscode": "^1.11.0"
  },
  "contributes": {
    "snippets": [
      {
        "language": "kotlin",
        "path": "./kotlin.json"
      },
      {
        "language": "go",
        "path": "./go.json"
      },
      {
        "language": "javascript",
        "path": "./react.json"
      },
      {
        "language": "typescript",
        "path": "./react.json"
      },
      {
        "language": "javascriptreact",
        "path": "./react.json"
      },
      {
        "language": "typescriptreact",
        "path": "./react.json"
      }
    ]
  }
}
EOF

    # Generate kotlin.json
    cat <<'EOF' > "${snippets_dir}/kotlin.json"
{
  "Import Compose Common": {
    "prefix": "impcomp",
    "body": [
      "import androidx.compose.runtime.Composable",
      "import androidx.compose.ui.tooling.preview.Preview",
      "import androidx.compose.runtime.remember",
      "import androidx.compose.runtime.getValue",
      "import androidx.compose.runtime.setValue",
      "import androidx.compose.runtime.mutableStateOf",
      "import androidx.compose.ui.Modifier",
      "import androidx.compose.ui.Alignment",
      "import androidx.compose.foundation.layout.Box",
      "import androidx.compose.foundation.layout.Column",
      "import androidx.compose.foundation.layout.Row",
      "import androidx.compose.foundation.layout.fillMaxSize",
      "import androidx.compose.foundation.layout.padding",
      "import androidx.compose.ui.unit.dp",
      "import androidx.compose.material3.Text",
      "import androidx.compose.material3.TextField",
      "import androidx.compose.material3.OutlinedTextField",
      "import androidx.compose.foundation.lazy.LazyColumn",
      "import androidx.compose.foundation.lazy.items"
    ],
    "description": "Import commonly used Jetpack Compose classes"
  },
  "Import ViewModel and Lifecycle": {
    "prefix": "impvm",
    "body": [
      "import androidx.lifecycle.ViewModel",
      "import androidx.lifecycle.viewmodel.compose.viewModel",
      "import androidx.lifecycle.viewModelScope",
      "import kotlinx.coroutines.flow.MutableStateFlow",
      "import kotlinx.coroutines.flow.asStateFlow",
      "import kotlinx.coroutines.launch"
    ],
    "description": "Import commonly used ViewModel and Lifecycle classes"
  },
  "ViewModel Boilerplate": {
    "prefix": "viewmodel",
    "body": [
      "import androidx.lifecycle.ViewModel",
      "import androidx.lifecycle.viewModelScope",
      "import kotlinx.coroutines.flow.MutableStateFlow",
      "import kotlinx.coroutines.flow.asStateFlow",
      "import kotlinx.coroutines.launch",
      "",
      "class ${1:My}ViewModel : ViewModel() {",
      "    private val _uiState = MutableStateFlow(${2:InitialState}())",
      "    val uiState = _uiState.asStateFlow()",
      "",
      "    fun onEvent(${3:event}: ${4:Event}) {",
      "        viewModelScope.launch {",
      "            $0",
      "        }",
      "    }",
      "}"
    ],
    "description": "Create a new Jetpack Compose compatible ViewModel boilerplate"
  },
  "Composable Function": {
    "prefix": "comp",
    "body": [
      "@Composable",
      "fun ${1:MyComponent}(",
      "    modifier: Modifier = Modifier",
      ") {",
      "    $0",
      "}"
    ],
    "description": "Create a Jetpack Compose @Composable function"
  },
  "Composable Preview": {
    "prefix": "prev",
    "body": [
      "@Preview(showBackground = true)",
      "@Composable",
      "fun ${1:MyComponent}Preview() {",
      "    ${1:MyComponent}()",
      "}"
    ],
    "description": "Create a Jetpack Compose @Preview function"
  },
  "Composable Preview (Dark/Light)": {
    "prefix": "prevd",
    "body": [
      "@Preview(name = \"Light Mode\", showBackground = true)",
      "@Preview(name = \"Dark Mode\", uiMode = android.content.res.Configuration.UI_MODE_NIGHT_YES, showBackground = true)",
      "@Composable",
      "fun ${1:MyComponent}Preview() {",
      "    ${1:MyComponent}()",
      "}"
    ],
    "description": "Create a @Preview function for Light and Dark modes"
  },
  "remember mutableStateOf": {
    "prefix": "rem",
    "body": [
      "val ${1:state} = remember { mutableStateOf(${2:initialValue}) }"
    ],
    "description": "Create a remembered state"
  },
  "remember mutableStateOf (by delegation)": {
    "prefix": "remby",
    "body": [
      "var ${1:state} by remember { mutableStateOf(${2:initialValue}) }"
    ],
    "description": "Create a remembered delegate state"
  },
  "Column Layout": {
    "prefix": "col",
    "body": [
      "Column(",
      "    modifier = ${1:Modifier},",
      "    verticalArrangement = Arrangement.${2:Top},",
      "    horizontalAlignment = Alignment.${3:Start}",
      ") {",
      "    $0",
      "}"
    ],
    "description": "Create a Column layout"
  },
  "Row Layout": {
    "prefix": "row",
    "body": [
      "Row(",
      "    modifier = ${1:Modifier},",
      "    horizontalArrangement = Arrangement.${2:Start},",
      "    verticalAlignment = Alignment.${3:Top}",
      ") {",
      "    $0",
      "}"
    ],
    "description": "Create a Row layout"
  },
  "Box Layout": {
    "prefix": "box",
    "body": [
      "Box(",
      "    modifier = ${1:Modifier},",
      "    contentAlignment = Alignment.${2:TopStart}",
      ") {",
      "    $0",
      "}"
    ],
    "description": "Create a Box layout"
  },
  "LazyColumn Layout": {
    "prefix": "lcol",
    "body": [
      "LazyColumn(",
      "    modifier = ${1:Modifier},",
      "    contentPadding = PaddingValues(${2:16.dp}),",
      "    verticalArrangement = Arrangement.spacedBy(${3:8.dp})",
      ") {",
      "    items(${4:itemsList}) { item ->",
      "        $0",
      "    }",
      "}"
    ],
    "description": "Create a LazyColumn for lists"
  },
  "LazyRow Layout": {
    "prefix": "lrow",
    "body": [
      "LazyRow(",
      "    modifier = ${1:Modifier},",
      "    contentPadding = PaddingValues(${2:16.dp}),",
      "    horizontalArrangement = Arrangement.spacedBy(${3:8.dp})",
      ") {",
      "    items(${4:itemsList}) { item ->",
      "        $0",
      "    }",
      "}"
    ],
    "description": "Create a LazyRow for horizontal lists"
  },
  "Scaffold Boilerplate": {
    "prefix": "scaffold",
    "body": [
      "Scaffold(",
      "    modifier = ${1:Modifier},",
      "    topBar = {",
      "        ${2:// TopBar}",
      "    },",
      "    bottomBar = {",
      "        ${3:// BottomBar}",
      "    },",
      "    floatingActionButton = {",
      "        ${4:// FloatingActionButton}",
      "    }",
      ") { innerPadding ->",
      "    Box(modifier = Modifier.padding(innerPadding)) {",
      "        $0",
      "    }",
      "}"
    ],
    "description": "Create a Scaffold template"
  },
  "LaunchedEffect": {
    "prefix": "launchedeffect",
    "body": [
      "LaunchedEffect(key1 = ${1:true}) {",
      "    $0",
      "}"
    ],
    "description": "Create a LaunchedEffect side effect block"
  },
  "rememberCoroutineScope": {
    "prefix": "scope",
    "body": [
      "val ${1:coroutineScope} = rememberCoroutineScope()"
    ],
    "description": "Get a coroutine scope in Composable"
  },
  "Text Composable": {
    "prefix": "txt",
    "body": [
      "Text(",
      "    text = \"${1:text}\",",
      "    modifier = ${2:Modifier},",
      "    style = MaterialTheme.typography.${3:bodyLarge}",
      ")"
    ],
    "description": "Create a Text Composable"
  },
  "Button Composable": {
    "prefix": "btn",
    "body": [
      "Button(",
      "    onClick = { ${1:// onClick action} },",
      "    modifier = ${2:Modifier}",
      ") {",
      "    Text(text = \"${3:Button Text}\")",
      "}"
    ],
    "description": "Create a Button Composable"
  },
  "Image Composable": {
    "prefix": "img",
    "body": [
      "Image(",
      "    painter = painterResource(id = R.drawable.${1:ic_launcher_foreground}),",
      "    contentDescription = \"${2:description}\",",
      "    modifier = ${3:Modifier}",
      ")"
    ],
    "description": "Create an Image Composable"
  },
  "Spacer Helper": {
    "prefix": "spacer",
    "body": [
      "Spacer(modifier = Modifier.${1:height}(${2:16.dp}))"
    ],
    "description": "Create a Spacer composable"
  },
  "Room Entity": {
    "prefix": "roomentity",
    "body": [
      "import androidx.room.Entity",
      "import androidx.room.PrimaryKey",
      "",
      "@Entity(tableName = \"${1:tableName}s\")",
      "data class ${2:EntityName}(",
      "    @PrimaryKey(autoGenerate = true) val id: Int = 0,",
      "    val ${3:field}: ${4:Type},",
      "    val isSynced: Boolean = false",
      ")"
    ],
    "description": "Create a Room Database Entity"
  },
  "Room DAO": {
    "prefix": "roomdao",
    "body": [
      "import androidx.room.*",
      "import kotlinx.coroutines.flow.Flow",
      "",
      "@Dao",
      "interface ${1:EntityName}Dao {",
      "    @Query(\"SELECT * FROM ${2:tableName}s ORDER BY ${3:date} DESC\")",
      "    fun getAll${1:EntityName}s(): Flow<List<${4:EntityClass}>>",
      "",
      "    @Query(\"SELECT * FROM ${2:tableName}s ORDER BY ${3:date} DESC LIMIT :limit\")",
      "    fun getLatest${1:EntityName}s(limit: Int): Flow<List<${4:EntityClass}>>",
      "",
      "    @Insert(onConflict = OnConflictStrategy.REPLACE)",
      "    suspend fun insert${1:EntityName}(${5:entity}: ${4:EntityClass})",
      "",
      "    @Delete",
      "    suspend fun delete${1:EntityName}(${5:entity}: ${4:EntityClass})",
      "",
      "    @Query(\"SELECT * FROM ${2:tableName}s WHERE isSynced = 0\")",
      "    suspend fun getUnsynced${1:EntityName}s(): List<${4:EntityClass}>",
      "",
      "    @Query(\"UPDATE ${2:tableName}s SET isSynced = 1 WHERE id IN (:ids)\")",
      "    suspend fun mark${1:EntityName}sAsSynced(ids: List<Int>)",
      "}"
    ],
    "description": "Create a Room Database DAO with Flow queries and sync helpers"
  },
  "Room Database": {
    "prefix": "roomdb",
    "body": [
      "import androidx.room.Database",
      "import androidx.room.RoomDatabase",
      "",
      "@Database(entities = [${1:EntityClass}::class], version = ${2:1}, exportSchema = false)",
      "abstract class ${3:AppDatabase} : RoomDatabase() {",
      "    abstract fun ${4:entityName}Dao(): ${1:EntityClass}Dao",
      "}"
    ],
    "description": "Create a Room Database abstract class"
  },
  "Retrofit API Service": {
    "prefix": "retrofitapi",
    "body": [
      "import retrofit2.Response",
      "import retrofit2.http.*",
      "",
      "interface ${1:ApiService} {",
      "    @GET(\"${2:endpoint}\")",
      "    suspend fun get${3:Data}(): Response<List<${4:ModelClass}>>",
      "",
      "    @POST(\"${2:endpoint}\")",
      "    suspend fun create${3:Data}(@Body ${5:body}: ${4:ModelClass}): Response<${4:ModelClass}>",
      "}"
    ],
    "description": "Create a Retrofit API Service Interface"
  },
  "Retrofit Client Instance": {
    "prefix": "retrofitclient",
    "body": [
      "import okhttp3.OkHttpClient",
      "import okhttp3.logging.HttpLoggingInterceptor",
      "import retrofit2.Retrofit",
      "import retrofit2.converter.gson.GsonConverterFactory",
      "",
      "object ${1:RetrofitClient} {",
      "    private const val BASE_URL = \"${2:https://api.example.com/}\"",
      "",
      "    private val okHttpClient by lazy {",
      "        OkHttpClient.Builder()",
      "            .addInterceptor(HttpLoggingInterceptor().apply {",
      "                level = HttpLoggingInterceptor.Level.BODY",
      "            })",
      "            .build()",
      "    }",
      "",
      "    val apiService: ${3:ApiService} by lazy {",
      "        Retrofit.Builder()",
      "            .baseUrl(BASE_URL)",
      "            .client(okHttpClient)",
      "            .addConverterFactory(GsonConverterFactory.create())",
      "            .build()",
      "            .create(${3:ApiService}::class.java)",
      "    }",
      "}"
    ],
    "description": "Create a Retrofit Client Singleton Instance with OkHttp Logging"
  }
}
EOF

    # Generate go.json
    cat <<'EOF' > "${snippets_dir}/go.json"
{
  "GORM Import": {
    "prefix": "gormimport",
    "body": [
      "import (",
      "\t\"gorm.io/gorm\"",
      "\t\"gorm.io/driver/${1:sqlite}\"",
      ")"
    ],
    "description": "Import GORM and a driver"
  },
  "GORM Connect": {
    "prefix": "gormconnect",
    "body": [
      "db, err := gorm.Open(${1:sqlite}.Open(\"${2:database.db}\"), &gorm.Config{})",
      "if err != nil {",
      "\tlog.Fatalf(\"failed to connect database: %v\", err)",
      "}"
    ],
    "description": "Initialize a GORM database connection"
  },
  "GORM Model": {
    "prefix": "gormmodel",
    "body": [
      "type ${1:ModelName} struct {",
      "\tgorm.Model",
      "\t${2:FieldName} ${3:FieldType} `gorm:\"${4:column:field_name}\"`",
      "}"
    ],
    "description": "Declare a GORM Model struct"
  },
  "GORM AutoMigrate": {
    "prefix": "gormmigrate",
    "body": [
      "err = db.AutoMigrate(&${1:ModelName}{})",
      "if err != nil {",
      "\tlog.Fatalf(\"failed to auto migrate: %v\", err)",
      "}"
    ],
    "description": "Auto migrate a schema"
  },
  "GORM Create": {
    "prefix": "gormcreate",
    "body": [
      "result := db.Create(&${1:variable})",
      "if result.Error != nil {",
      "\t${2:// handle error}",
      "}"
    ],
    "description": "Create a new record in GORM"
  },
  "GORM First": {
    "prefix": "gormfirst",
    "body": [
      "var ${1:result} ${2:ModelName}",
      "err := db.First(&${1:result}, ${3:id}).Error",
      "if err != nil {",
      "\t${4:// handle error}",
      "}"
    ],
    "description": "Query first record by ID"
  },
  "GORM Find All": {
    "prefix": "gormfind",
    "body": [
      "var ${1:results} []${2:ModelName}",
      "err := db.Find(&${1:results}).Error",
      "if err != nil {",
      "\t${3:// handle error}",
      "}"
    ],
    "description": "Query all records matching criteria"
  },
  "GORM Where Query": {
    "prefix": "gormwhere",
    "body": [
      "var ${1:results} []${2:ModelName}",
      "err := db.Where(\"${3:query}\", ${4:arg}).Find(&${1:results}).Error",
      "if err != nil {",
      "\t${5:// handle error}",
      "}"
    ],
    "description": "Query records with a WHERE clause"
  },
  "GORM Update": {
    "prefix": "gormupdate",
    "body": [
      "err := db.Model(&${1:modelInstance}).Update(\"${2:FieldName}\", ${3:value}).Error",
      "if err != nil {",
      "\t${4:// handle error}",
      "}"
    ],
    "description": "Update a single field of a record"
  },
  "GORM Updates Map/Struct": {
    "prefix": "gormupdates",
    "body": [
      "err := db.Model(&${1:modelInstance}).Updates(${2:ModelName}{${3:FieldName}: ${4:value}}).Error",
      "if err != nil {",
      "\t${5:// handle error}",
      "}"
    ],
    "description": "Update multiple fields using struct or map"
  },
  "GORM Delete": {
    "prefix": "gormdelete",
    "body": [
      "err := db.Delete(&${1:modelInstance}, ${2:id}).Error",
      "if err != nil {",
      "\t${3:// handle error}",
      "}"
    ],
    "description": "Delete a record"
  },
  "GORM Transaction": {
    "prefix": "gormtx",
    "body": [
      "err = db.Transaction(func(tx *gorm.DB) error {",
      "\tif err := tx.Create(&${1:model}).Error; err != nil {",
      "\t\treturn err",
      "\t}",
      "\treturn nil",
      "})"
    ],
    "description": "Execute database operations within a transaction"
  }
}
EOF

    # Generate react.json
    cat <<'EOF' > "${snippets_dir}/react.json"
{
  "React HTML Table": {
    "prefix": "rtable",
    "body": [
      "<table>",
      "  <thead>",
      "    <tr>",
      "      <th>${1:Header}</th>",
      "    </tr>",
      "  </thead>",
      "  <tbody>",
      "    {${2:items}.map((${3:item}) => (",
      "      <tr key={${3:item}.${4:id}}>",
      "        <td>{${3:item}.${5:property}}</td>",
      "      </tr>",
      "    ))}",
      "  </tbody>",
      "</table>"
    ],
    "description": "Create an HTML table in React with map => tr loop"
  },
  "React Default Export Component": {
    "prefix": "rfc",
    "body": [
      "import React from 'react';",
      "",
      "interface ${1:ComponentName}Props {",
      "  ${2:// props}",
      "}",
      "",
      "export default function ${1:ComponentName}({ ${3:props} }: ${1:ComponentName}Props) {",
      "  return (",
      "    <div>",
      "      $0",
      "    </div>",
      "  );",
      "}"
    ],
    "description": "Create a React functional component with default export"
  },
  "React Query - useQuery": {
    "prefix": "usequery",
    "body": [
      "import { useQuery } from '@tanstack/react-query';",
      "",
      "const { data, isLoading, error } = useQuery({",
      "  queryKey: ['${1:queryKey}'],",
      "  queryFn: ${2:fetchFunction}",
      "});"
    ],
    "description": "Create a React Query useQuery hook instance"
  },
  "React Query - useMutation": {
    "prefix": "usemutation",
    "body": [
      "import { useMutation, useQueryClient } from '@tanstack/react-query';",
      "",
      "const queryClient = useQueryClient();",
      "",
      "const { mutate, isPending, error } = useMutation({",
      "  mutationFn: ${1:mutationFunction},",
      "  onSuccess: () => {",
      "    queryClient.invalidateQueries({ queryKey: ['${2:queryKey}'] });",
      "  }",
      "});"
    ],
    "description": "Create a React Query useMutation hook instance"
  },
  "React Context and Provider": {
    "prefix": "reactcontext",
    "body": [
      "import React, { createContext, useContext, useState, ReactNode } from 'react';",
      "",
      "interface ${1:ContextName}Type {",
      "  ${2:state}: ${3:any};",
      "  set${2:state}: React.Dispatch<React.SetStateAction<${3:any}>>;",
      "}",
      "",
      "const ${1:ContextName}Context = createContext<${1:ContextName}Type | undefined>(undefined);",
      "",
      "export function ${1:ContextName}Provider({ children }: { children: ReactNode }) {",
      "  const [${2:state}, set${2:state}] = useState<${3:any}>(${4:initialValue});",
      "",
      "  return (",
      "    <${1:ContextName}Context.Provider value={{ ${2:state}, set${2:state} }}>",
      "      {children}",
      "    </${1:ContextName}Context.Provider>",
      "  );",
      "}",
      "",
      "export function use${1:ContextName}() {",
      "  const context = useContext(${1:ContextName}Context);",
      "  if (context === undefined) {",
      "    throw new Error('use${1:ContextName} must be used within a ${1:ContextName}Provider');",
      "  }",
      "  return context;",
      "}"
    ],
    "description": "Create a React context, provider component, and custom hook"
  },
  "React Dynamic Refs Map": {
    "prefix": "dynamicrefs",
    "body": [
      "import { useRef } from 'react';",
      "",
      "const ${1:refsMap} = useRef<Map<${2:string}, ${3:HTMLElement} | null>>(null);",
      "",
      "const getMap = () => {",
      "  if (!${1:refsMap}.current) {",
      "    ${1:refsMap}.current = new Map();",
      "  }",
      "  return ${1:refsMap}.current;",
      "};",
      "",
      "// Usage in render: ref={node => { const map = getMap(); if (node) { map.set(key, node); } else { map.delete(key); } }}"
    ],
    "description": "Create React dynamic refs template utilizing Map"
  }
}
EOF
    echo "Neovim snippets updated successfully!"
}

_make_android_autocomplete() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="init create model component build install run dev logs stop clean all help wifi"

    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
    return 0
}
complete -F _make_android_autocomplete make-android
