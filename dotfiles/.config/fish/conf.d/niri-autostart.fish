# Niri TTY Autostart
# Auto-launches Niri on tty1/tty2 after systemd getty autologin.

if status is-login
    # Prevent infinite recursion when niri-session spawns a login shell to import env vars
    if not set -q IN_NIRI_LOGIN_LAUNCHER
        set -l current_tty (tty)
        if string match -q '/dev/tty1' $current_tty; or string match -q '/dev/tty2' $current_tty
            if not set -q WAYLAND_DISPLAY; and not set -q DISPLAY
                set -gx IN_NIRI_LOGIN_LAUNCHER 1
                ~/.config/niri/scripts/niri-tty.fish
            end
        end
    end
end
