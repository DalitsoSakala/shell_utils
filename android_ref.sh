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

.PHONY: all build install run clean logs dev stop help wifi preview

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
	@echo "  build    Build the debug APK"
	@echo "  install  Install the APK on connected device/emulator"
	@echo "  run      Launch the main activity"
	@echo "  preview  Generate Compose screenshot previews (FILE=SomeFile.kt)"
	@echo "  dev      Build, install, and run the app (default)"
	@echo "  logs     Stream Logcat output for the app"
	@echo "  stop     Stop app process on device"
	@echo "  clean    Clean build artifacts"
	@echo "  wifi     Discover and connect to devices over Wi-Fi"
	@echo "  help     Show this help message"
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

.PHONY: all build install run clean logs dev stop help wifi preview

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
	@echo "  build    Build the debug APK"
	@echo "  install  Install the APK on connected device/emulator"
	@echo "  run      Launch the main activity"
	@echo "  preview  Generate Compose screenshot previews (FILE=SomeFile.kt)"
	@echo "  dev      Build, install, and run the app (default)"
	@echo "  logs     Stream Logcat output for the app"
	@echo "  stop     Stop app process on device"
	@echo "  clean    Clean build artifacts"
	@echo "  wifi     Discover and connect to devices over Wi-Fi"
	@echo "  help     Show this help message"
EOF
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
    opts="init create build install run dev logs stop clean all help wifi"

    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
    return 0
}
complete -F _make_android_autocomplete make-android
