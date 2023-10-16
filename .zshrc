export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="af-magic-custom"
CASE_SENSITIVE="true"
export UPDATE_ZSH_DAYS=7
HIST_STAMPS="yyyy-mm-dd"

plugins=(zsh-syntax-highlighting asdf rails git ruby tmux aws bundler fzf ssh-agent tmux)

zstyle :omz:plugins:ssh-agent agent-forwarding on
zstyle  :omz:plugins:ssh-agent identities netengine

source $ZSH/oh-my-zsh.sh

export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:$HOME/.local/bin:$HOME/.yarn/bin
export LANG=en_US.UTF-8
export EDITOR='vim'
export TERM=xterm-256color
export PGHOST=localhost
# export GEM_HOME=$HOME/.gems/

case $OSTYPE in
  linux-gnu)
    export BROWSER=/opt/google/chrome/google-chrome
    ;;
  darwin*)
    export BROWSER="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
esac

alias vi="vim"
alias tmux="tmux -2"
alias git-clean-master='git branch --merged master | grep -Ev "\b(main|master)\b" | xargs -n 1 git branch -d && git remote prune origin'
alias git-clean-main='git branch --merged main | grep -Ev "\b(main|master)\b" | xargs -n 1 git branch -d && git remote prune origin'
alias git-clean-staging='git branch --merged staging | grep -Ev "\b(staging)\b" | xargs -n 1 git branch -d && git remote prune origin'
alias git-clean-danggling='git fetch --all -p ; git branch -vv | awk "/: gone]/ { print $1 }" | xargs -r -n 1 git branch -D'
alias less='less -R'
alias cop="git status --porcelain | awk '\$1 ~ /A|M/ && \$NF ~ /\.rb$/ { print \$NF }' | xargs rubocop --force-exclusion"
alias deploy-capistrano='docker run -ti --rm -v $(pwd)/../../.ssh:/root/.ssh -v $(pwd):/app -w /app ruby:3.0.4 sh -c "bundle install && cap production deploy"'
alias brew-update='brew bundle --file=./Brewfile --cleanup'

if [ "$OSTYPE" = "linux-gnu" ]; then
  alias open="xdg-open"
fi

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

ecs_exec() {
  scout_uat="scouttalent-development-scout-sidekiq"
  scout_prod_ca="scouttalent-prod-ca-scout-sidekiq"
  scout_prod_au="scouttalent-prod-au-scout-sidekiq"

  region=$1
  normalized_region=$(echo $region | tr '-' '_')
  service=$(eval echo \$${normalized_region})

  task_id=`aws ecs list-tasks --cluster ecs_cluster --service ${service} --profile ${region} | jq -r '.taskArns[0]' | cut -d '/' -f3`

  echo "Accessing task $task_id in $region"

  aws ecs execute-command \
    --cluster ecs_cluster \
    --task $task_id \
    --container app \
    --interactive \
    --command "bash" \
    --profile $1
}

ssm_exec() {
  profile=$1

  case $1 in
    scout-uat)
      instance_id="i-03cc50fe62add2417"
      ;;
    scout-prod-au)
      instance_id="i-0486990b6c3d0f704"
      ;;
    scout-prod-ca)
      instance_id="i-0815d2b6b362c102e"
      ;;
    *)
      echo "Do not know this profile"
      ;;
  esac

  aws ssm start-session \
    --target $instance_id --profile $profile
}