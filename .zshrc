export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="af-magic-custom"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(zsh-syntax-highlighting rails git ruby tmux aws bundler nvm fzf node npm rvm ssh-agent)

zstyle :omz:plugins:ssh-agent agent-forwarding on
zstyle :omz:plugins:ssh-agent identities netengine

source $ZSH/oh-my-zsh.sh

export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:$HOME/.local/bin
export LANG=en_US.UTF-8
export EDITOR='vim'
export TERM=xterm-256color
export PGHOST=localhost

case $OSTYPE in
  linux-gnu)
    export BROWSER=/opt/google/chrome/google-chrome
    . /usr/share/fzf/key-bindings.zsh
    alias open="xdg-open"
    ;;
  darwin*)
    export BROWSER="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
    . /usr/local/Cellar/fzf/0.22.0/shell/key-bindings.zsh
esac

alias vi="vim"
alias tmux="tmux -2"
alias git-clean='git branch --merged master | grep -v "\* master" | xargs -n 1 git branch -d && git remote prune origin'
alias less='less -R'
alias mplayer-iso='mplayer dvd:// -dvd-device'

# place this after nvm initialization!
autoload -U add-zsh-hook
load-nvmrc() {
  local node_version="$(nvm version)"
  local nvmrc_path="$(nvm_find_nvmrc)"

  if [ -n "$nvmrc_path" ]; then
    local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

    if [ "$nvmrc_node_version" = "N/A" ]; then
      nvm install >/dev/null
    elif [ "$nvmrc_node_version" != "$node_version" ]; then
      nvm use > /dev/null
    fi
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc

if [ -x "/usr/bin/ksshaskpass" ]; then
  export SSH_ASKPASS="/usr/bin/ksshaskpass"
fi

export GPG_TTY=$(tty)
[ -f $HOME/.gnupg/gpg-agent-info ] && source $HOME/.gnupg/gpg-agent-info
if [ -S "${GPG_AGENT_INFO%%:*}" ]; then
  export GPG_AGENT_INFO
else
  eval $( gpg-agent --daemon --options $HOME/.gnupg/gpg-agent.conf )
fi

[[ $HOME/bin/kubectl ]] && source <(kubectl completion zsh)
