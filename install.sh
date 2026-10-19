#!/usr/bin/env bash
# Install the opencode-code-review agents into an OpenCode V2 configuration.
set -euo pipefail

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
AGENTS=(code-reviewer.md review-lens.md)

SCOPE="global"
TARGET=""
LINK=0
UNINSTALL=0
DRY_RUN=0
FORCE=0

usage() {
  cat <<'EOF'
Install the code-reviewer and review-lens agents for OpenCode V2.

Usage:
  ./install.sh [options]

Options:
  --global             Install for the current user (default).
  --project [DIR]      Install into DIR/.opencode/agents (DIR defaults to the
                       current directory).
  --agents-dir DIR     Install directly into DIR, which must be the agents
                       directory itself (advanced).
  --link               Symlink the agents instead of copying them, so `git pull`
                       updates them in place. Keep the clone afterwards.
  --uninstall          Remove the agents installed by this repository.
  --dry-run            Print what would happen without changing anything.
  --force              Overwrite or remove modified agent files without a
                       backup or skip.
  -h, --help           Show this help.

Examples:
  ./install.sh
  ./install.sh --project
  ./install.sh --project ~/code/my-app
  ./install.sh --link
  ./install.sh --uninstall
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

say() {
  printf '%s\n' "$*"
}

# Back up an existing path next to itself, avoiding collisions.
backup_path() {
  local path="$1" stamp backup n
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$path.bak.$stamp"
  n=1
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="$path.bak.$stamp.$n"
    n=$((n + 1))
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    say "would back up $path -> $backup"
  else
    mv -- "$path" "$backup"
    say "backed up $path -> $backup"
  fi
}

# Resolve OpenCode's global config directory, falling back to XDG paths.
global_config_dir() {
  local detected=""
  if command -v opencode >/dev/null 2>&1; then
    detected="$(opencode debug paths config 2>/dev/null || true)"
  fi
  if [ -n "$detected" ]; then
    printf '%s\n' "$detected"
  elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s\n' "$XDG_CONFIG_HOME/opencode"
  else
    printf '%s\n' "$HOME/.config/opencode"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --global)
      SCOPE="global"
      TARGET=""
      shift
      ;;
    --project)
      SCOPE="project"
      TARGET=""
      shift
      if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
        TARGET="$1"
        shift
      fi
      ;;
    --project=*)
      SCOPE="project"
      TARGET="${1#*=}"
      shift
      ;;
    --agents-dir)
      [ "$#" -ge 2 ] || die "--agents-dir requires a directory"
      SCOPE="custom"
      TARGET="$2"
      shift 2
      ;;
    --agents-dir=*)
      SCOPE="custom"
      TARGET="${1#*=}"
      shift
      ;;
    --link)
      LINK=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$SCOPE" in
  global)
    DEST="$(global_config_dir)/agents"
    ;;
  project)
    BASE="${TARGET:-$PWD}"
    [ -d "$BASE" ] || die "project directory does not exist: $BASE"
    DEST="$BASE/.opencode/agents"
    ;;
  custom)
    [ -n "$TARGET" ] || die "--agents-dir requires a directory"
    DEST="$TARGET"
    ;;
esac

for name in "${AGENTS[@]}"; do
  [ -f "$REPO_DIR/agents/$name" ] || die "missing source file: $REPO_DIR/agents/$name"
done

if command -v opencode >/dev/null 2>&1; then
  version="$(opencode --version 2>/dev/null || true)"
  case "$version" in
    "" | *2.*) ;;
    *) say "warning: these agents target OpenCode V2, but '$version' was detected." ;;
  esac
else
  say "note: 'opencode' is not on PATH. Install OpenCode V2 from https://opencode.ai."
fi

changed=0
skipped=0
current=0

for name in "${AGENTS[@]}"; do
  src="$REPO_DIR/agents/$name"
  dest="$DEST/$name"

  if [ "$UNINSTALL" -eq 1 ]; then
    if [ -L "$dest" ]; then
      link_target="$(readlink -- "$dest" || true)"
      if [ "$link_target" = "$src" ] || [ "$FORCE" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "would remove $dest"
        else
          rm -- "$dest"
          say "removed $dest"
        fi
        changed=$((changed + 1))
      else
        say "skipped $dest (symlink points elsewhere; use --force to remove)"
        skipped=$((skipped + 1))
      fi
    elif [ -f "$dest" ]; then
      if cmp -s -- "$src" "$dest" || [ "$FORCE" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "would remove $dest"
        else
          rm -- "$dest"
          say "removed $dest"
        fi
        changed=$((changed + 1))
      else
        say "skipped $dest (local changes; use --force to remove)"
        skipped=$((skipped + 1))
      fi
    else
      say "not installed: $dest"
      current=$((current + 1))
    fi
    continue
  fi

  if [ "$LINK" -eq 1 ]; then
    if [ -L "$dest" ] && [ "$(readlink -- "$dest")" = "$src" ]; then
      say "up to date: $dest"
      current=$((current + 1))
      continue
    fi

    if [ -L "$dest" ] || [ -e "$dest" ]; then
      if [ "$FORCE" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "would remove $dest"
        else
          rm -f -- "$dest"
        fi
      else
        backup_path "$dest"
      fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      say "would link $dest -> $src"
    else
      mkdir -p -- "$DEST"
      ln -s -- "$src" "$dest"
      say "linked $dest -> $src"
    fi
    changed=$((changed + 1))
    continue
  fi

  if [ -f "$dest" ] && cmp -s -- "$src" "$dest"; then
    say "up to date: $dest"
    current=$((current + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ "$FORCE" -eq 1 ]; then
        say "would replace $dest"
      else
        say "would back up existing $dest"
      fi
    fi
    say "would install $dest"
  else
    mkdir -p -- "$DEST"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ "$FORCE" -eq 1 ]; then
        rm -f -- "$dest"
      else
        backup_path "$dest"
      fi
    fi
    cp -- "$src" "$dest"
    say "installed $dest"
  fi
  changed=$((changed + 1))
done

say ""

if [ "$UNINSTALL" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "Dry run: would remove $changed agent(s) from $DEST."
  elif [ "$changed" -eq 0 ]; then
    say "No agents removed from $DEST."
  else
    say "Removed $changed agent(s) from $DEST."
  fi
  if [ "$skipped" -gt 0 ]; then
    say "Skipped $skipped modified file(s); re-run with --force to remove them."
  fi
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run: would install $changed agent(s) into $DEST."
  exit 0
fi

if [ "$changed" -eq 0 ]; then
  say "Agents already up to date in $DEST."
else
  say "Installed $changed agent(s) into $DEST."
fi

if [ "$LINK" -eq 1 ]; then
  say "Agents are symlinked to $REPO_DIR; keep that clone and run 'git pull' to update them."
fi

if command -v opencode >/dev/null 2>&1; then
  say "Reload OpenCode configuration: opencode reload"
fi
say "Run a review: opencode run --agent code-reviewer \"Review the current changes\""
