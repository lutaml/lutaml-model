#!/usr/bin/env bash
# Installs Ghostscript for ukiryu's required PDF smoke tests only.
# The shared tool-setup-action no longer provisions it. Runs from the dependent
# checkout (after-setup-ruby hook, working-directory: dependent).
set -euo pipefail

if [ ! -f ukiryu.gemspec ]; then
  echo "setup-dependent-tools: not ukiryu, nothing to install"
  exit 0
fi

add_path() {
  if [ -n "${GITHUB_PATH:-}" ]; then
    # Git Bash uses /c/... locally; the Windows runner needs a native path.
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -w "$1" >> "$GITHUB_PATH"
    else
      printf '%s\n' "$1" >> "$GITHUB_PATH"
    fi
  fi
  export PATH="$1:$PATH"
}

case "$(uname -s)" in
  Linux)
    sudo apt-get update
    sudo apt-get install -y ghostscript
    ;;
  Darwin)
    brew install ghostscript
    add_path "$(brew --prefix)/bin"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    choco install -y ghostscript
    for d in /c/ProgramData/chocolatey/bin; do
      [ -d "$d" ] && add_path "$d"
    done
    for d in /c/Program\ Files/gs/gs*/bin; do
      [ -d "$d" ] && add_path "$d"
    done
    ;;
  *)
    echo "setup-dependent-tools: unsupported OS $(uname -s)" >&2
    exit 1
    ;;
esac

# Fail the step, not the later spec, if a tool is not reachable.
if command -v gs >/dev/null 2>&1; then gs --version
else gswin64c --version; fi
