#!/bin/sh
set -eu

install_dir="${RPATH_INSTALL_DIR:-}"
wrappers="${RPATH_INSTALL_WRAPPERS:-ask}"
yes=0
purge=0
dry_run=0

usage() {
  cat <<'USAGE'
rpath uninstaller

Usage: uninstall.sh [options]

Options:
  --install-dir <dir>       Install directory. Defaults to installer metadata or ~/.local/bin.
  --yes                    Accept prompts, including detected shell wrapper removal.
  --wrappers <mode>        ask, yes, no, or all. Defaults to ask.
  --purge                  Remove rpath state such as snapshots and versions.
  --dry-run                Print what would happen without writing.
  -h, --help               Show this help.

Environment:
  RPATH_INSTALL_DIR
  RPATH_INSTALL_WRAPPERS
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir)
      install_dir="${2:-}"
      shift 2
      ;;
    --install-dir=*)
      install_dir="${1#*=}"
      shift
      ;;
    --yes|-y)
      yes=1
      shift
      ;;
    --wrappers)
      wrappers="${2:-}"
      shift 2
      ;;
    --wrappers=*)
      wrappers="${1#*=}"
      shift
      ;;
    --purge)
      purge=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$wrappers" in
  ask|yes|no|all) ;;
  *)
    echo "--wrappers must be one of: ask, yes, no, all" >&2
    exit 1
    ;;
esac

state_root="${XDG_DATA_HOME:-$HOME/.local/share}"
state_dir="$state_root/rpath"
metadata_file="$state_dir/install.env"

metadata_value() {
  key="$1"
  [ -f "$metadata_file" ] || return 0
  sed -n "s/^$key=//p" "$metadata_file" | tail -n 1
}

if [ -z "$install_dir" ]; then
  install_dir="$(metadata_value install_dir)"
fi
if [ -z "$install_dir" ]; then
  install_dir="$HOME/.local/bin"
fi

binary_path="$install_dir/rpath"
if [ ! -x "$binary_path" ] && command -v rpath >/dev/null 2>&1; then
  wrapper_binary="$(command -v rpath)"
else
  wrapper_binary="$binary_path"
fi

detect_shell() {
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    bash|zsh|fish) printf '%s' "$shell_name" ;;
    *) printf '' ;;
  esac
}

is_interactive() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_yes_no() {
  prompt="$1"
  if ! is_interactive; then
    return 1
  fi
  printf '%s [y/N] ' "$prompt" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

run_wrapper_uninstall() {
  mode="$1"
  if [ ! -x "$wrapper_binary" ]; then
    echo "rpath binary not found; skipping shell wrapper removal"
    return
  fi

  if [ "$mode" = "all" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo "dry run: would run $wrapper_binary uninstall --all"
    else
      "$wrapper_binary" uninstall --all || true
    fi
    return
  fi

  shell_name="$(detect_shell)"
  if [ -z "$shell_name" ]; then
    echo "could not detect a supported shell for wrapper removal; run rpath uninstall manually"
    return
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would run $wrapper_binary uninstall --shell $shell_name"
  else
    "$wrapper_binary" uninstall --shell "$shell_name" || true
  fi
}

maybe_uninstall_wrappers() {
  case "$wrappers" in
    no)
      echo "skipping shell wrapper removal"
      ;;
    yes|all)
      run_wrapper_uninstall "$wrappers"
      ;;
    ask)
      if [ "$yes" -eq 1 ]; then
        run_wrapper_uninstall "yes"
      elif prompt_yes_no "Remove the rpath shell wrapper for the detected shell now?"; then
        run_wrapper_uninstall "yes"
      else
        echo "skipping shell wrapper removal"
      fi
      ;;
  esac
}

remove_marked_block() {
  profile="$1"
  [ -f "$profile" ] || return 0
  if ! grep -q ">>> rpath binary path >>>" "$profile"; then
    return 0
  fi
  tmp_file="$profile.rpath-uninstall.$$"
  awk '
    /# >>> rpath binary path >>>/ { skip = 1; next }
    /# <<< rpath binary path <<</ { skip = 0; next }
    !skip { print }
  ' "$profile" > "$tmp_file"
  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would remove rpath PATH block from $profile"
    rm -f "$tmp_file"
  else
    mv "$tmp_file" "$profile"
    echo "removed rpath PATH block from $profile"
  fi
}

remove_path_blocks() {
  metadata_profile="$(metadata_value path_profile)"
  profiles="$HOME/.bashrc $HOME/.zshrc $HOME/.profile $HOME/.config/fish/config.fish"
  if [ -n "$metadata_profile" ]; then
    profiles="$metadata_profile $profiles"
  fi
  seen=""
  for profile in $profiles; do
    case " $seen " in
      *" $profile "*) continue ;;
    esac
    seen="$seen $profile"
    remove_marked_block "$profile"
  done
}

echo "rpath uninstaller"
echo "install directory: $install_dir"

maybe_uninstall_wrappers
remove_path_blocks

if [ -e "$binary_path" ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would remove $binary_path"
  else
    rm -f "$binary_path"
    echo "removed $binary_path"
  fi
else
  echo "binary not found at $binary_path"
fi

if [ "$purge" -eq 1 ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would remove state directory $state_dir"
  else
    rm -rf "$state_dir"
    echo "removed state directory $state_dir"
  fi
elif [ -f "$metadata_file" ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would remove install metadata $metadata_file"
  else
    rm -f "$metadata_file"
    echo "removed install metadata"
  fi
fi

echo "rpath uninstall complete"
