function changelockavatar --description 'Change lock screen avatar'
    if test (count $argv) -eq 0
        echo "Usage: changelockavatar /path/to/avatar.jpg"
        return 1
    end

    set -l target_file (realpath $argv[1])
    if not test -f "$target_file"
        echo "Error: File '$argv[1]' does not exist."
        return 1
    end

    set -l target_ext (string lower (string split -r -m1 . $target_file)[2])

    if test "$target_ext" = "png"
        ln -sf "$target_file" ~/.config/hypr/lock_avatar.png
        echo "Lock screen avatar successfully changed to: $target_file"
    else
        echo "Converting non-PNG avatar to PNG format..."
        set -l converted_file ~/.config/hypr/lock_avatar_converted.png
        convert "$target_file" png:"$converted_file"
        ln -sf "$converted_file" ~/.config/hypr/lock_avatar.png
        echo "Lock screen avatar converted and successfully changed to: $target_file"
    end
end
