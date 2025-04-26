export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="minimal"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(
  rails
  git
  nvm
  yarn
  ruby
  aws
  bundler
  fzf
  rbenv
  ssh-agent
  gpg-agent
  tmux
  zsh-syntax-highlighting
)

zstyle :omz:plugins:ssh-agent agent-forwarding on
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent identities eduardo
zstyle :omz:plugins:nvm autoload yes
zstyle :omz:plugins:nvm silent-autoload yes
zstyle :omz:alpha:lib:git async-prompt false;

source $ZSH/oh-my-zsh.sh

export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:$HOME/.local/bin:$HOME/.yarn/bin
export LANG=en_US.UTF-8
export EDITOR='vim'
export TERM=xterm-256color
export PGHOST=localhost

alias vi="vim"
alias tmux="tmux -2"
alias git-clean-master='git branch --merged master | grep -Ev "\b(main|master)\b" | xargs -n 1 git branch -d && git remote prune origin'
alias git-clean-main='git branch --merged main | grep -Ev "\b(main|master)\b" | xargs -n 1 git branch -d && git remote prune origin'
alias git-clean-danggling='git fetch --all -p ; git branch -vv | awk "/: gone]/ { print $1 }" | xargs -r -n 1 git branch -D'
alias less='less -R'
alias cop="git status --porcelain | awk '\$1 ~ /A|M/ && \$NF ~ /\.rb$/ { print \$NF }' | xargs rubocop --force-exclusion"
alias brew-update='brew bundle --file=~/Brewfile --cleanup'

if type -p xdg-open &> /dev/null ; then
  alias open="xdg-open"
fi

if type -p ksshaskpass &> /dev/null ; then
  export SSH_ASKPASS="/usr/bin/ksshaskpass"
fi

alias fif='
  ag --nogroup --column  --hidden --ignore .git . | fzf --prompt "Ag> " \
    --ansi --preview "/usr/bin/bash \"$HOME/.vim/pack/plugins/start/fzf.vim/bin/preview.sh\" {}" \
    --multi --delimiter ":" --preview-window "+{2}/2" --accept-nth=1 | xargs -r vim -p --not-a-term'

export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1
