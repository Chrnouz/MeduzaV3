#!/bin/sh

set -eu

OS_NAME="$(uname -s 2>/dev/null || printf '%s' 'unknown')"

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || {
    printf '[ERROR] Unable to determine script directory.\n' >&2
    exit 1
}

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    COLOR_INFO='\033[1;36m'
    COLOR_WARN='\033[1;33m'
    COLOR_ERROR='\033[1;31m'
    COLOR_RESET='\033[0m'
else
    COLOR_INFO=''
    COLOR_WARN=''
    COLOR_ERROR=''
    COLOR_RESET=''
fi

log() {
    printf '%b[INFO]%b %s\n' "$COLOR_INFO" "$COLOR_RESET" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "$COLOR_WARN" "$COLOR_RESET" "$*" >&2
}

die() {
    printf '%b[ERROR]%b %s\n' "$COLOR_ERROR" "$COLOR_RESET" "$*" >&2
    exit 1
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "Root privileges required. Install sudo or run as root."
    fi
}

find_python() {
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
    elif command -v python >/dev/null 2>&1; then
        command -v python
    else
        return 1
    fi
}

detect_platform() {
    case "${PREFIX:-}" in
        *com.termux*|*/termux/*)
            PLATFORM="termux"
            return 0
            ;;
    esac

    if [ -n "${TERMUX_VERSION:-}" ]; then
        PLATFORM="termux"
        return 0
    fi

    case "$OS_NAME" in
        Darwin)
            PLATFORM="macos"
            ;;
        Linux)
            PLATFORM="linux"
            ;;
        *)
            PLATFORM="unknown"
            ;;
    esac
}

is_shared_storage() {
    case "$SCRIPT_DIR" in
        /sdcard|/sdcard/*|/storage/*|/mnt/media_rw/*|"${HOME:-}/storage"|"${HOME:-}/storage/"*)
            return 0
            ;;
    esac

    return 1
}

set_venv_dir() {
    if [ -n "${VENV_DIR:-}" ]; then
        case "$VENV_DIR" in
            /*)
                ;;
            *)
                VENV_DIR="$SCRIPT_DIR/$VENV_DIR"
                ;;
        esac
    elif [ "$PLATFORM" = "termux" ] && is_shared_storage; then
        [ -n "${HOME:-}" ] || die "HOME is not set in Termux."

        VENV_DIR="$HOME/.venvs/$(basename "$SCRIPT_DIR")"

        warn "Project is on shared storage. Virtual environment will be stored in Termux HOME."
    else
        VENV_DIR="$SCRIPT_DIR/.venv"
    fi
}

install_python() {
    log "Checking Python environment..."

    case "$PLATFORM" in
        termux)
            command -v pkg >/dev/null 2>&1 ||
                die "Termux package manager (pkg) not found. Use the official Termux app."

            pkg update -y ||
                die "Termux repository update failed. Check your network or run termux-change-repo."

            pkg install -y \
                python \
                python-pip \
                python-ensurepip-wheels ||
                die "Unable to install Python and pip packages in Termux."

            if grep -Eiq '^[[:space:]]*aiohttp([<=>[:space:]-]|$)' "$SCRIPT_DIR/requirements.txt"; then
                log "Installing Termux build tools for aiohttp dependencies..."

                pkg install -y \
                    clang \
                    make \
                    pkg-config ||
                    die "Unable to install build tools required by aiohttp."
            fi
            ;;

        macos)
            if ! command -v python3 >/dev/null 2>&1; then
                if command -v brew >/dev/null 2>&1; then
                    brew install python ||
                        die "Homebrew failed to install Python."
                else
                    die "Python 3 is missing. Install Homebrew from https://brew.sh/ and rerun."
                fi
            fi
            ;;

        linux)
            if command -v apt-get >/dev/null 2>&1; then
                run_as_root apt-get update ||
                    die "apt-get update failed."

                run_as_root apt-get install -y \
                    python3 \
                    python3-pip \
                    python3-venv ||
                    die "Unable to install Python packages with apt-get."

            elif command -v dnf >/dev/null 2>&1; then
                run_as_root dnf install -y \
                    python3 \
                    python3-pip ||
                    die "Unable to install Python packages with dnf."

            elif command -v yum >/dev/null 2>&1; then
                run_as_root yum install -y \
                    python3 \
                    python3-pip ||
                    die "Unable to install Python packages with yum."

            elif command -v pacman >/dev/null 2>&1; then
                run_as_root pacman -S --needed --noconfirm \
                    python \
                    python-pip ||
                    die "Unable to install Python packages with pacman."

            elif command -v zypper >/dev/null 2>&1; then
                run_as_root zypper --non-interactive install \
                    python3 \
                    python3-pip \
                    python3-virtualenv ||
                    die "Unable to install Python packages with zypper."

            elif command -v apk >/dev/null 2>&1; then
                run_as_root apk add \
                    python3 \
                    py3-pip \
                    py3-virtualenv ||
                    die "Unable to install Python packages with apk."

            elif ! command -v python3 >/dev/null 2>&1; then
                die "No supported package manager or Python 3 installation found."
            else
                warn "Unsupported package manager. Using the existing Python installation."
            fi
            ;;

        *)
            if ! command -v python3 >/dev/null 2>&1 &&
                ! command -v python >/dev/null 2>&1; then
                die "Unsupported OS. Python 3 is required."
            fi
            ;;
    esac
}

create_venv() {
    log "Preparing virtual environment: $VENV_DIR"

    mkdir -p "$(dirname "$VENV_DIR")" ||
        die "Unable to create virtual environment parent directory."

    if [ ! -x "$VENV_DIR/bin/python" ]; then
        if ! "$PYTHON_BIN" -m venv "$VENV_DIR"; then
            if command -v virtualenv >/dev/null 2>&1; then
                warn "python -m venv failed. Trying virtualenv..."

                virtualenv -p "$PYTHON_BIN" "$VENV_DIR" ||
                    die "Unable to create virtual environment."
            else
                die "Unable to create virtual environment. Install the venv support package."
            fi
        fi
    else
        log "Existing virtual environment detected. Reusing it."
    fi

    VENV_PY="$VENV_DIR/bin/python"

    [ -x "$VENV_PY" ] ||
        die "Virtual environment Python executable not found."

    "$VENV_PY" --version >/dev/null 2>&1 ||
        die "Virtual environment Python cannot be executed."
}

main() {
    [ -f "$SCRIPT_DIR/requirements.txt" ] ||
        die "requirements.txt not found."

    [ -f "$SCRIPT_DIR/go.py" ] ||
        die "go.py not found."

    detect_platform
    set_venv_dir

    cd "$SCRIPT_DIR"

    log "Detected platform: $PLATFORM"
    log "Project directory: $SCRIPT_DIR"

    if [ "$PLATFORM" = "linux" ] &&
        [ -r /etc/os-release ] &&
        grep -Eiq 'kali|nethunter' /etc/os-release; then
        log "Kali / NetHunter environment detected."
    fi

    install_python

    PYTHON_BIN="$(find_python || true)"

    [ -n "$PYTHON_BIN" ] ||
        die "Python installation failed."

    log "Using Python: $PYTHON_BIN"

    "$PYTHON_BIN" --version ||
        die "Python is not executable."

    create_venv

    if ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
        log "Bootstrapping pip in virtual environment..."

        "$VENV_PY" -m ensurepip --upgrade ||
            die "Unable to bootstrap pip. On Termux install python-pip and python-ensurepip-wheels."
    fi

    log "Upgrading pip, setuptools, and wheel..."

    "$VENV_PY" -m pip install --upgrade \
        pip \
        setuptools \
        wheel ||
        die "Unable to upgrade pip build tools. Check your network connection."

    log "Installing requirements..."

    "$VENV_PY" -m pip install \
        -r "$SCRIPT_DIR/requirements.txt" ||
        die "Dependency installation failed. Review the pip error above."

    log "Checking installed dependency consistency..."

    "$VENV_PY" -m pip check ||
        die "Installed Python dependencies are inconsistent."

    log "Setup completed successfully."
    log "Starting go.py..."

    exec "$VENV_PY" "$SCRIPT_DIR/go.py" "$@"
}

main "$@"
