#!/bin/bash
# =============================================================================
#  EDITOR WRAPPER — core/lib/editor.sh
#
#  Provides a consistent way to open files in a text editor across
#  all Igor subsystems. Respects $EDITOR, falls back to micro → nano → vi.
#
#  Lazy-loaded: source this file on first use via:
#    declare -f igor_edit_file >/dev/null || source "${IGOR_DIR}/core/lib/editor.sh"
#
#  Public API:
#    igor_detect_editor          — sets IGOR_EDITOR; called automatically
#    igor_edit_file <path> [desc] — open a file, return 0 if changed, 1 if not
#    igor_offer_install_micro     — offer to install micro if no editor found
# =============================================================================

# IGOR_EDITOR is set by igor_detect_editor and persists for the session.
IGOR_EDITOR="${IGOR_EDITOR:-}"

# ---------------------------------------------------------------------------
# igor_detect_editor
#
#   Determines the editor to use. Priority:
#     1. $EDITOR environment variable (if set and available)
#     2. micro
#     3. nano
#     4. vi
#     5. "cat" fallback (shows the file, no editing)
#
#   Sets and exports IGOR_EDITOR.
# ---------------------------------------------------------------------------
igor_detect_editor() {
    # Already detected this session
    [ -n "$IGOR_EDITOR" ] && return 0

    # 1. Respect user's $EDITOR preference
    if [ -n "${EDITOR:-}" ] && command -v "$EDITOR" >/dev/null 2>&1; then
        IGOR_EDITOR="$EDITOR"
        return 0
    fi

    # 2. Preference order: micro → nano → vi
    local _ed
    for _ed in micro nano vi; do
        if command -v "$_ed" >/dev/null 2>&1; then
            IGOR_EDITOR="$_ed"
            return 0
        fi
    done

    # 3. Last resort — at least show the file
    IGOR_EDITOR="cat"
    return 0
}

# ---------------------------------------------------------------------------
# igor_offer_install_micro
#
#   If no proper editor is found (IGOR_EDITOR = "cat"), offer to install micro.
#   micro is a single static binary (~10 MB, no deps).
#   Only calls out if a confirm() function is available (ui.sh loaded).
# ---------------------------------------------------------------------------
igor_offer_install_micro() {
    [ "$IGOR_EDITOR" != "cat" ] && return 0
    command -v micro >/dev/null 2>&1 && { IGOR_EDITOR="micro"; return 0; }

    printf '\n  No text editor found. micro is a lightweight terminal editor (~10 MB).\n'
    if declare -f confirm >/dev/null 2>&1; then
        if confirm "Install micro editor now?"; then
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL https://getmic.ro/r | bash
            elif command -v wget >/dev/null 2>&1; then
                wget -qO- https://getmic.ro/r | bash
            else
                printf '  Cannot download: curl and wget both missing.\n'
                return 1
            fi
            # Move to a location on PATH
            if [ -f ./micro ]; then
                if mv ./micro /usr/local/bin/micro 2>/dev/null; then
                    IGOR_EDITOR="micro"
                elif mkdir -p "$HOME/.local/bin" && mv ./micro "$HOME/.local/bin/micro"; then
                    IGOR_EDITOR="$HOME/.local/bin/micro"
                else
                    printf '  micro downloaded but could not be moved to PATH.\n'
                    IGOR_EDITOR="./micro"
                fi
            fi
        fi
    else
        printf '  Install with: curl https://getmic.ro/r | bash\n'
        printf '  Or set $EDITOR to your preferred editor.\n'
    fi
    return 0
}

# ---------------------------------------------------------------------------
# igor_edit_file <filepath> [description]
#
#   Opens <filepath> in the detected editor. Prints a brief header showing
#   the file, editor, and optional description.
#
#   Returns:
#     0  — file was modified (mtime changed)
#     1  — file unchanged or editor not found
#
#   The caller can use the return code to decide whether to reload config,
#   restart services, etc.
# ---------------------------------------------------------------------------
igor_edit_file() {
    local _filepath="${1:-}"
    local _description="${2:-}"

    if [ -z "$_filepath" ]; then
        printf '  [editor] igor_edit_file: no file path given\n' >&2
        return 1
    fi

    if [ ! -f "$_filepath" ] && [ ! -e "$_filepath" ]; then
        printf '  [editor] File not found: %s\n' "$_filepath" >&2
        return 1
    fi

    igor_detect_editor

    if [ "$IGOR_EDITOR" = "cat" ]; then
        igor_offer_install_micro
    fi

    # Print context header
    printf '\n'
    if [ -n "$_description" ]; then
        printf '  Editing:  %s\n' "$_description"
    fi
    printf '  File:     %s\n' "$_filepath"
    printf '  Editor:   %s\n' "$IGOR_EDITOR"
    printf '\n'

    # Capture mtime before edit
    local _mtime_before
    _mtime_before=$(stat -c '%Y' "$_filepath" 2>/dev/null || echo "0")

    # Open the editor
    $IGOR_EDITOR "$_filepath"

    # Capture mtime after edit
    local _mtime_after
    _mtime_after=$(stat -c '%Y' "$_filepath" 2>/dev/null || echo "0")

    if [ "$_mtime_before" != "$_mtime_after" ]; then
        printf '  File modified.\n\n'
        return 0
    else
        printf '  No changes.\n\n'
        return 1
    fi
}
