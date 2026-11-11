
#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/.venv}"
OS_NAME="$(uname -s)"

cd "$SCRIPT_DIR"

log() {
    printf '\033[1;36m[INFO]\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$1" >&2
}

die() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2
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
        *com.termux*)
            PLATFORM="termux"
            ;;
        *)
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
            ;;
    esac
}

install_python() {
    log "Installing Python and pip..."

    case "$PLATFORM" in
        termux)
            command -v pkg >/dev/null 2>&1 ||
                die "Termux package manager not found."

            pkg update -y
            pkg install -y python
            ;;

        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install python
            elif command -v python3 >/dev/null 2>&1; then
                warn "Homebrew not found. Using existing Python."
            else
                die "Install Homebrew first: https://brew.sh/"
            fi
            ;;

        linux)
            if command -v apt-get >/dev/null 2>&1; then
                run_as_root apt-get update
                run_as_root apt-get install -y \
                    python3 python3-pip python3-venv

            elif command -v dnf >/dev/null 2>&1; then
                run_as_root dnf install -y \
                    python3 python3-pip

            elif command -v yum >/dev/null 2>&1; then
                run_as_root yum install -y \
                    python3 python3-pip

            elif command -v pacman >/dev/null 2>&1; then
                run_as_root pacman -S --needed --noconfirm \
                    python python-pip

            elif command -v zypper >/dev/null 2>&1; then
                run_as_root zypper --non-interactive install \
                    python3 python3-pip python3-virtualenv

            elif command -v apk >/dev/null 2>&1; then
                run_as_root apk add \
                    python3 py3-pip py3-virtualenv

            elif command -v python3 >/dev/null 2>&1; then
                warn "Unsupported package manager. Using existing Python."

            else
                die "No supported package manager or Python installation found."
            fi
            ;;

        *)
            if ! command -v python3 >/dev/null 2>&1; then
                die "Unsupported OS. Python 3 is required."
            fi
            ;;
    esac
}

create_venv() {
    log "Creating virtual environment..."

    if "$PYTHON_BIN" -m venv "$VENV_DIR"; then
        return 0
    fi

    if command -v virtualenv >/dev/null 2>&1; then
        warn "Python venv unavailable. Falling back to virtualenv."
        virtualenv -p "$PYTHON_BIN" "$VENV_DIR"
        return 0
    fi

    die "Unable to create virtual environment. Install the Python venv package."
}

main() {
    [ -f "$SCRIPT_DIR/requirements.txt" ] ||
        die "requirements.txt not found."

    [ -f "$SCRIPT_DIR/go.py" ] ||
        die "go.py not found."

    detect_platform

    log "Detected platform: $PLATFORM"

    if [ "$PLATFORM" = "linux" ] && [ -r /etc/os-release ]; then
        if grep -Eiq 'kali|nethunter' /etc/os-release; then
            log "Kali / NetHunter environment detected."
        fi
    fi

    install_python

    PYTHON_BIN="$(find_python || true)"

    [ -n "$PYTHON_BIN" ] ||
        die "Python installation failed."

    log "Python version:"
    "$PYTHON_BIN" --version

    create_venv

    VENV_PY="$VENV_DIR/bin/python"

    [ -x "$VENV_PY" ] ||
        die "Virtual environment Python executable not found."

    if ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
        log "Bootstrapping pip..."
        "$VENV_PY" -m ensurepip --upgrade ||
            die "Unable to install pip in virtual environment."
    fi

    log "Upgrading pip..."
    "$VENV_PY" -m pip install --upgrade pip

    log "Installing requirements..."
    "$VENV_PY" -m pip install -r "$SCRIPT_DIR/requirements.txt"

    log "Setup completed successfully."
    log "Starting go.py..."

    exec "$VENV_PY" "$SCRIPT_DIR/go.py" "$@"
}

main "$@"
