# Niri TTY Autostart
# Auto-launches Niri on tty1/tty2 after systemd getty autologin.

if status is-login
    set -l current_tty (tty)
    if string match -q '/dev/tty1' $current_tty; or string match -q '/dev/tty2' $current_tty
        if not set -q WAYLAND_DISPLAY; and not set -q DISPLAY
            ~/.config/niri/scripts/niri-tty.fish
        end
    end
end
