#!/usr/bin/fish

set -q NIRI_TTY_TIMEOUT; or set NIRI_TTY_TIMEOUT 5

function wait_for_resource
    set -l path $argv[1]
    set -l name $argv[2]
    set -l test_type $argv[3]; or set test_type -e
    set -l max_iterations (math "$NIRI_TTY_TIMEOUT * 5")
    set -l count 0

    while not test $test_type $path
        if test $count -ge $max_iterations
            echo "ERROR: $name ($path) not available after $NIRI_TTY_TIMEOUT seconds"
            return 1
        end
        sleep 0.2
        set count (math $count + 1)
    end

    return 0
end

echo "=== Niri TTY Launcher ==="
echo "TTY: "(tty)
echo "User: "(whoami)" (UID: "(id -u)")"

set -gx XDG_SESSION_CLASS user
set -gx XDG_SESSION_TYPE wayland
set -gx XDG_CURRENT_DESKTOP niri
set -gx XDG_RUNTIME_DIR /run/user/(id -u)
set -gx QT_QPA_PLATFORM wayland
set -gx ELECTRON_OZONE_PLATFORM_HINT wayland

if not wait_for_resource "$XDG_RUNTIME_DIR" "runtime directory" -d
    echo "Check if pam_systemd is configured correctly."
    echo "Press Enter to exit..."
    read
    exit 1
end

if command -q niri-session
    echo "Starting Niri through niri-session..."
    exec niri-session
else if command -q niri
    echo "Starting Niri directly..."
    exec niri --session
else
    echo "ERROR: niri-session or niri was not found in PATH."
    echo "Press Enter to exit..."
    read
    exit 1
end
