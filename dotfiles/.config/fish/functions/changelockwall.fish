function changelockwall --description 'Change lock screen wallpaper'
    if test (count $argv) -eq 0
        echo "Usage: changelockwall /path/to/image.png"
        return 1
    end

    set -l target_file (realpath $argv[1])
    if not test -f "$target_file"
        echo "Error: File '$argv[1]' does not exist."
        return 1
    end

    ln -sf "$target_file" ~/.config/hypr/lock_wallpaper.png
    echo "Lock screen wallpaper successfully changed to: $target_file"
end
