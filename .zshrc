export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="af-magic"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(zsh-syntax-highlighting rails git ruby tmux aws bundler nvm fzf node npm rvm ssh-agent tmux)

zstyle :omz:plugins:ssh-agent agent-forwarding on
zstyle  :omz:plugins:ssh-agent identities netengine

source $ZSH/oh-my-zsh.sh

export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:$HOME/.local/bin:$HOME/.yarn/bin:$HOME/.rvm/bin
export LANG=en_US.UTF-8
export EDITOR='vim'
export TERM=xterm-256color
export PGHOST=localhost

case $OSTYPE in
  linux-gnu)
    export BROWSER=/opt/google/chrome/google-chrome
    ;;
  darwin*)
    export BROWSER="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
esac

alias vi="vim"
alias tmux="tmux -2"
alias git-clean='git branch --merged master | grep -v "\* master" | xargs -n 1 git branch -d && git remote prune origin'
alias less='less -R'
alias mplayer-iso='mplayer dvd:// -dvd-device'
alias cop="git status --porcelain | awk '\$1 ~ /A|M/ && \$NF ~ /\.rb$/ { print \$NF }' | xargs rubocop --force-exclusion"

if [ "$OSTYPE" = "linux-gnu" ]; then
  alias open="xdg-open"
fi

export NVM_DIR="$HOME/.nvm"
[ -f "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

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

. /usr/local/Cellar/fzf/0.22.0/shell/key-bindings.zsh
