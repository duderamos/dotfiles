export ZSH=/home/eduardo/.oh-my-zsh

ZSH_THEME="af-magic"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(zsh-syntax-highlighting rails git ruby tmux aws bundler nvm fzf node npm rvm ssh-agent tmux)

zstyle :omz:plugins:ssh-agent agent-forwarding on
zstyle :omz:plugins:ssh-agent identities netengine

source $ZSH/oh-my-zsh.sh

export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:$HOME/.local/bin:$HOME/.yarn/bin:$HOME/.rvm/bin
export LANG=en_US.UTF-8
export TERM=xterm-256color
export EDITOR='vim'
export BROWSER=/opt/google/chrome/google-chrome
export PGHOST=localhost

alias vi="vim"
alias tmux="tmux -2"
alias git-clean='git branch --merged master | grep -v "\* master" | xargs -n 1 git branch -d && git remote prune origin'
alias less='less -R'
alias tmux-template='~/bin/tmux-template.sh'
alias cp='cp --reflink=auto'
alias mplayer-iso='mplayer dvd:// -dvd-device'
alias cop="git status --porcelain | awk '\$1 ~ /A|M/ && \$NF ~ /\.rb$/ { print \$NF }' | xargs rubocop --force-exclusion"
alias open="xdg-open"

export NVM_DIR="/home/eduardo/.nvm"
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

export SSH_ASKPASS="/usr/bin/ksshaskpass"

export GPG_TTY=$(tty)
[ -f ~/.gnupg/gpg-agent-info ] && source ~/.gnupg/gpg-agent-info
if [ -S "${GPG_AGENT_INFO%%:*}" ]; then
    export GPG_AGENT_INFO
else
    eval $( gpg-agent --daemon --options ~/.gnupg/gpg-agent.conf )
fi

[[ /home/eduardo/bin/kubectl ]] && source <(kubectl completion zsh)

. /usr/share/fzf/key-bindings.zsh
