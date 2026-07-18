#!/bin/sh
set -eu

repo="rpathdev/rpath"
version="${RPATH_VERSION:-latest}"
install_dir="${RPATH_INSTALL_DIR:-$HOME/.local/bin}"
wrappers="${RPATH_INSTALL_WRAPPERS:-ask}"
yes=0
no_path=0
dry_run=0

usage() {
  cat <<'USAGE'
rpath installer

Usage: install.sh [options]

Options:
  --version <version>       Install a release tag. Defaults to latest.
  --install-dir <dir>       Install directory. Defaults to ~/.local/bin.
  --yes                    Accept prompts, including detected shell wrapper install.
  --no-path                Do not add the install directory to PATH.
  --wrappers <mode>        ask, yes, no, or all. Defaults to ask.
  --dry-run                Print what would happen without downloading or writing.
  -h, --help               Show this help.

Environment:
  RPATH_VERSION
  RPATH_INSTALL_DIR
  RPATH_INSTALL_WRAPPERS
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --version=*)
      version="${1#*=}"
      shift
      ;;
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
    --no-path)
      no_path=1
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

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
  else
    echo "missing required command: curl or wget" >&2
    exit 1
  fi
}

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{ print tolower($1) }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{ print tolower($1) }'
  else
    echo "missing required command: sha256sum or shasum" >&2
    exit 1
  fi
}

detect_artifact() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
  esac

  case "$os:$arch" in
    Linux:x86_64) artifact="rpath-linux-x86_64" ;;
    Linux:aarch64) artifact="rpath-linux-aarch64" ;;
    Darwin:x86_64) artifact="rpath-macos-x86_64" ;;
    Darwin:aarch64) artifact="rpath-macos-aarch64" ;;
    *)
      echo "unsupported platform: $os/$arch" >&2
      exit 1
      ;;
  esac

  archive_name="$artifact.tar.gz"
  checksum_name="$archive_name.sha256"
  binary_name="rpath"
}

release_base_url() {
  if [ "$version" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download' "$repo"
    return
  fi

  case "$version" in
    v*) tag="$version" ;;
    *) tag="v$version" ;;
  esac
  printf 'https://github.com/%s/releases/download/%s' "$repo" "$tag"
}

quote_for_sh() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

detect_shell() {
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    bash|zsh|fish) printf '%s' "$shell_name" ;;
    *) printf '' ;;
  esac
}

path_profile_for_shell() {
  shell_name="$(detect_shell)"
  case "$shell_name" in
    zsh) printf '%s/.zshrc' "$HOME" ;;
    fish) printf '%s/.config/fish/config.fish' "$HOME" ;;
    bash) printf '%s/.bashrc' "$HOME" ;;
    *) printf '%s/.profile' "$HOME" ;;
  esac
}

append_path_profile() {
  profile="$1"
  dir="$2"
  mkdir -p "$(dirname "$profile")"
  if [ -f "$profile" ] && grep -q ">>> rpath binary path >>>" "$profile"; then
    return
  fi

  escaped_dir="$(quote_for_sh "$dir")"
  if [ "$(basename "$profile")" = "config.fish" ]; then
    {
      printf '\n# >>> rpath binary path >>>\n'
      printf "set -l rpath_bin_dir '%s'\n" "$escaped_dir"
      printf 'if not contains -- $rpath_bin_dir $PATH\n'
      printf '    fish_add_path $rpath_bin_dir\n'
      printf 'end\n'
      printf '# <<< rpath binary path <<<\n'
    } >> "$profile"
  else
    {
      printf '\n# >>> rpath binary path >>>\n'
      printf "RPATH_BIN_DIR='%s'\n" "$escaped_dir"
      printf 'case ":$PATH:" in\n'
      printf '  *":$RPATH_BIN_DIR:"*) ;;\n'
      printf '  *) export PATH="$RPATH_BIN_DIR:$PATH" ;;\n'
      printf 'esac\n'
      printf '# <<< rpath binary path <<<\n'
    } >> "$profile"
  fi
}

write_metadata() {
  state_root="${XDG_DATA_HOME:-$HOME/.local/share}"
  state_dir="$state_root/rpath"
  mkdir -p "$state_dir"
  {
    printf 'install_dir=%s\n' "$install_dir"
    printf 'binary=%s\n' "$binary_path"
    printf 'path_profile=%s\n' "${path_profile:-}"
  } > "$state_dir/install.env"
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

run_wrapper_install() {
  mode="$1"
  if [ "$mode" = "all" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo "dry run: would run $binary_path install --all"
    else
      "$binary_path" install --all
    fi
    return
  fi

  shell_name="$(detect_shell)"
  if [ -z "$shell_name" ]; then
    echo "could not detect a supported shell for wrapper installation; run rpath install manually"
    return
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "dry run: would run $binary_path install --shell $shell_name"
  else
    "$binary_path" install --shell "$shell_name"
  fi
}

maybe_install_wrappers() {
  case "$wrappers" in
    no)
      echo "skipping shell wrapper installation"
      ;;
    yes|all)
      run_wrapper_install "$wrappers"
      ;;
    ask)
      if [ "$yes" -eq 1 ]; then
        run_wrapper_install "yes"
      elif prompt_yes_no "Install the rpath shell wrapper for the detected shell now?"; then
        run_wrapper_install "yes"
      else
        echo "skipping shell wrapper installation; run rpath install later if you want live PATH refresh"
      fi
      ;;
  esac
}

detect_artifact
base_url="$(release_base_url)"
archive_url="$base_url/$archive_name"
checksum_url="$base_url/$checksum_name"
binary_path="$install_dir/$binary_name"
path_profile=""

echo "rpath installer"
echo "artifact: $archive_name"
echo "install directory: $install_dir"

if [ "$dry_run" -eq 1 ]; then
  echo "dry run: would download $archive_url"
  echo "dry run: would verify $checksum_url"
  echo "dry run: would install $binary_path"
  if [ "$no_path" -eq 0 ]; then
    echo "dry run: would add $install_dir to user PATH if missing"
  fi
  maybe_install_wrappers
  exit 0
fi

need tar
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

archive_path="$tmp_dir/$archive_name"
checksum_path="$tmp_dir/$checksum_name"
extract_dir="$tmp_dir/extract"
mkdir -p "$extract_dir"

download "$archive_url" "$archive_path"
download "$checksum_url" "$checksum_path"

expected="$(awk '{ print tolower($1); exit }' "$checksum_path")"
actual="$(sha256_file "$archive_path")"
if [ "$expected" != "$actual" ]; then
  echo "checksum mismatch for $archive_name" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

tar -xzf "$archive_path" -C "$extract_dir"
found_binary="$(find "$extract_dir" -type f -name "$binary_name" | head -n 1)"
if [ -z "$found_binary" ]; then
  echo "archive did not contain $binary_name" >&2
  exit 1
fi

mkdir -p "$install_dir"
cp "$found_binary" "$binary_path.tmp"
chmod 755 "$binary_path.tmp"
mv "$binary_path.tmp" "$binary_path"

if [ "$no_path" -eq 0 ]; then
  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *)
      path_profile="$(path_profile_for_shell)"
      append_path_profile "$path_profile" "$install_dir"
      echo "added $install_dir to PATH in $path_profile"
      ;;
  esac
fi

write_metadata
echo "installed rpath to $binary_path"
maybe_install_wrappers
echo "open a new terminal, then run: rpath --version"
