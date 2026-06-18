#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

[ -s /usr/share/nvm/init-nvm.sh ] && source /usr/share/nvm/init-nvm.sh


# Added by Antigravity CLI installer
export PATH="/home/vishvaa/.local/bin:$PATH"
. "$HOME/.cargo/env"
