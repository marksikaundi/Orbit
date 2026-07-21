# Orbit shell integration — enables `zig build run` from any directory.
# Installed by: zig build setup
# Sourced from ~/.zshrc / ~/.bashrc (added by setup).
#
# Behavior: if the current directory has no build.zig, `zig build …` is
# forwarded to the Orbit source tree recorded in ~/.config/orbit/source_root.
# Local Zig projects are never redirected.

# Avoid double-loading.
if [ -n "${ORBIT_SHELL_INTEGRATION:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
ORBIT_SHELL_INTEGRATION=1

_orbit_config_dir() {
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s/orbit' "$XDG_CONFIG_HOME"
  else
    printf '%s/.config/orbit' "${HOME:-}"
  fi
}

_orbit_source_root() {
  if [ -n "${ORBIT_SOURCE_ROOT:-}" ] && [ -f "${ORBIT_SOURCE_ROOT}/build.zig" ]; then
    printf '%s' "$ORBIT_SOURCE_ROOT"
    return 0
  fi
  local conf root
  conf="$(_orbit_config_dir)/source_root"
  if [ -f "$conf" ]; then
    root="$(tr -d '[:space:]' <"$conf" 2>/dev/null)" || root=""
    if [ -n "$root" ] && [ -f "$root/build.zig" ]; then
      printf '%s' "$root"
      return 0
    fi
  fi
  return 1
}

# Prepend ~/.local/bin when Orbit installed the binary there.
_orbit_local_bin="${HOME:-}/.local/bin"
if [ -d "$_orbit_local_bin" ]; then
  case ":${PATH:-}:" in
    *":${_orbit_local_bin}:"*) ;;
    *) PATH="${_orbit_local_bin}:${PATH:-}" ; export PATH ;;
  esac
fi
unset _orbit_local_bin

zig() {
  if [ "${1:-}" != "build" ]; then
    command zig "$@"
    return $?
  fi

  # Prefer a local Zig package in the current directory.
  if [ -f build.zig ] || [ -f build.zig.zon ]; then
    command zig "$@"
    return $?
  fi

  local root
  if ! root="$(_orbit_source_root)"; then
    command zig "$@"
    return $?
  fi

  shift # drop "build"
  # Run from the Orbit tree so relative paths in build.zig resolve.
  (cd "$root" && command zig build "$@")
}
