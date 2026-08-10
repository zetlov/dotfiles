# -----------------------
# PATH
# -----------------------
export PATH="$HOME/bin:/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

export CDPATH=".:$HOME:$HOME/links"

# -----------------------
# Oh My Zsh
# -----------------------
export ZSH="$HOME/.oh-my-zsh"

# Starship renders the prompt, so Oh My Zsh does not need a theme.
ZSH_THEME=""
plugins=(git)
_zsh_system_plugin_root="${ZSH_SYSTEM_PLUGIN_ROOT:-/usr/share/zsh/plugins}"
_zsh_system_plugin_files=()

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  for _zsh_plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    _zsh_plugin_file="${ZSH_CUSTOM:-$ZSH/custom}/plugins/$_zsh_plugin/$_zsh_plugin.plugin.zsh"
    if [[ -r "$_zsh_plugin_file" ]]; then
      plugins+=("$_zsh_plugin")
    else
      _zsh_plugin_file="$_zsh_system_plugin_root/$_zsh_plugin/$_zsh_plugin.zsh"
      [[ ! -r "$_zsh_plugin_file" ]] || _zsh_system_plugin_files+=("$_zsh_plugin_file")
    fi
  done
  source "$ZSH/oh-my-zsh.sh"
else
  # Keep fresh and server installs usable before Oh My Zsh is installed.
  for _zsh_plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    _zsh_plugin_file="$_zsh_system_plugin_root/$_zsh_plugin/$_zsh_plugin.zsh"
    [[ ! -r "$_zsh_plugin_file" ]] || _zsh_system_plugin_files+=("$_zsh_plugin_file")
  done
fi
for _zsh_plugin_file in "${_zsh_system_plugin_files[@]}"; do
  source "$_zsh_plugin_file"
done
unset _zsh_plugin _zsh_plugin_file _zsh_system_plugin_files _zsh_system_plugin_root

# -----------------------
# General
# -----------------------
# key bindings
bindkey -v

# Match the cursor shape to the active vi keymap without replacing existing
# Oh My Zsh widgets.
function _set_cursor_for_vi_mode() {
  case "$KEYMAP" in
    vicmd) printf '\e[2 q' ;;
    viins|main) printf '\e[6 q' ;;
  esac
}

function _reset_cursor_for_zle() {
  printf '\e[6 q'
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget keymap-select _set_cursor_for_vi_mode
add-zle-hook-widget line-init _reset_cursor_for_zle
add-zle-hook-widget line-finish _reset_cursor_for_zle

# enable autocomplete
autoload -U compinit ; compinit

# Herdr completion
if (( $+commands[herdr] )); then
  source <(herdr completion zsh)
fi

# use colors
autoload -Uz colors ; colors

# share history with other terminals
setopt share_history

# don't show duplicate history
setopt hist_ignore_all_dups

# don't add to history if commands start with space
setopt hist_ignore_space

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# move directory w/o cd command
setopt auto_cd
alias ...='cd ../..'
alias ....='cd ../../..'

# auto ls
function chpwd() { ls }

# auto pushd
setopt auto_pushd

# delete duplicates in pushd
setopt pushd_ignore_dups

# correct mistakes
setopt correct

# -----------------------
# Tools
# -----------------------
# opam configuration
[[ ! -r "$HOME/.opam/opam-init/init.zsh" ]] || source "$HOME/.opam/opam-init/init.zsh" > /dev/null 2> /dev/null

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# mise
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

# OpenClaw completion
[[ -r "$HOME/.openclaw/completions/openclaw.zsh" ]] && source "$HOME/.openclaw/completions/openclaw.zsh"

# ====== git worktree wrapper ======
function gwa() {
  local LIST_FILENAME=".worktree-copy-list"
  local DEFAULT_FILES=(".env" ".env.local" "mise.local.toml" "CLAUDE.local.md")

  # create worktree
  git worktree add "$@" || return 1

  # determine target dir
  local target_dir=""
  for arg in "$@"; do
    if [ -d "$arg" ] && [ -f "$arg/.git" ]; then
      target_dir="$arg"
      break
    fi
  done

  if [ -z "$target_dir" ]; then
    echo "Error: Worktree created, but path not detected for copying files."
    return 0
  fi

  # determine source root
  local source_root=$(git rev-parse --show-toplevel)

  # determine files to copy
  local files_to_copy=()

  if [ -f "$source_root/$LIST_FILENAME" ]; then
    echo "Found copy list: $LIST_FILENAME"
    # read lines from the list file
    while IFS= read -r line; do
      # skip empty lines and comments
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      files_to_copy+=("$line")
    done < "$source_root/$LIST_FILENAME"
  else
    echo "No custom list found. Using defaults."
    files_to_copy=("${DEFAULT_FILES[@]}")
  fi

  # copy files
  echo "Copying files to $target_dir..."
  local copy_count=0

  for file in "${files_to_copy[@]}"; do
    local src="$source_root/$file"
    local dest="$target_dir/$file"
    local dest_parent=$(dirname "$dest")

    if [ -d "$src" ]; then
      # directory: create it and copy contents recursively,
      # including hidden files, without an extra nesting level
      mkdir -p "$dest"
      cp -R "$src/." "$dest/"
      echo "   Copied (dir):  $file"
      ((copy_count++))
    elif [ -f "$src" ]; then
      [ ! -d "$dest_parent" ] && mkdir -p "$dest_parent"
      cp "$src" "$dest"
      echo "   Copied (file): $file"
      ((copy_count++))
    else
      echo "   Skipped: $file (not found)"
    fi
  done

  if [ $copy_count -eq 0 ]; then
    echo "   (No files were copied)"
  fi
}

# -----------------------
# Local overrides (untracked)
# -----------------------
# Machine-specific settings (include paths, work-only env vars, ...)
if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

# Secrets (API keys, tokens, ...)
if [ -f ~/.zsh_secrets ]; then
    source ~/.zsh_secrets
fi

if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

codex() {
    if (( $+commands[mise] )); then
        mise x npm:@openai/codex -- codex "$@"
        return
    fi

    command codex "$@"
}
