# Resolve the default Node.js version installed by NVM.
if test -r /usr/share/nvm/init-nvm.sh
    set -l nvm_node (bash -c 'source /usr/share/nvm/init-nvm.sh >/dev/null 2>&1; nvm which default' 2>/dev/null)
    if test -x "$nvm_node"
        set -l nvm_bin (dirname "$nvm_node")
        if not contains -- "$nvm_bin" $PATH
            set -gx PATH "$nvm_bin" $PATH
        end
    end
end
