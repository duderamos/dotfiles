export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="minimal"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(
  rails
  git
  git-prompt
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
zstyle :omz:plugins:ssh-agent identities tanda

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

function _find-edit {
  zle kill-whole-line
  zle -U 'vim $(fzf)'
  zle accept-line
}
zle -N _find-edit

bindkey "^P" _find-edit
alias search-open='vim $(fzf)'
