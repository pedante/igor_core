#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/scrub.sh
#  Central credential scrubbing engine.
#
#  Collects literal values and regex patterns from two sources, then filters
#  any text through them before it leaves the machine (AI API calls, logs):
#
#    • secrets/*.env scan       — every VALUE in every .env file
#    • module.conf [secrets]    — per-module variable names + regex patterns
#
#  All matches are replaced with [REDACTED].
#
#  Relationship to core/ai/scrub.sh:
#    ai_scrub_outbound() replaces known values with labelled tokens
#    ([IGOR:DOMAIN] etc.) so the AI can reason about them.  igor_scrub() is
#    called as a final pass to catch any remaining literals that the token
#    table did not cover.
#
#  Public API:
#    igor_scrub_register_literal <value>         — register a literal value
#    igor_scrub_register_pattern <ere_pattern>   — register an ERE regex
#    igor_scrub <text>                           — return scrubbed text
#    igor_scrub_load_module_secrets <module_dir> — load from module.conf [secrets]
#    igor_scrub_load_secrets_dir [dir]           — scan secrets/*.env for values
# ==============================================================================

# ── Registries ────────────────────────────────────────────────────────────────
# _IGOR_SCRUB_LITERALS : sed-escaped fixed strings (literal value matches)
# _IGOR_SCRUB_PATTERNS : raw ERE patterns
declare -ga _IGOR_SCRUB_LITERALS 2>/dev/null || true
declare -ga _IGOR_SCRUB_PATTERNS 2>/dev/null || true

# ---------------------------------------------------------------------------
# igor_scrub_register_literal <value>
#
#   Register a literal string for redaction.
#   The value is sed-escaped so it matches exactly.
#   Skips empty, whitespace-only, already-tokenised, or very short values
#   (< 4 chars) to avoid false positives in normal tool output.
# ---------------------------------------------------------------------------
igor_scrub_register_literal() {
    local _val="$1"

    # Guard: skip empty / too short / whitespace-only / already a token
    [ -n "$_val" ]                        || return 0
    [ "${#_val}" -ge 4 ]                  || return 0
    [[ "$_val" =~ ^[[:space:]]+$ ]]       && return 0
    [[ "$_val" =~ ^\[IGOR: ]]             && return 0

    # Escape for sed literal use (pipe is the s/// delimiter inside igor_scrub)
    local _escaped
    _escaped=$(printf '%s\n' "$_val" | sed 's/[.*^$[\]/\\&/g; s/|/\\|/g')

    # Dedup
    local _e
    for _e in "${_IGOR_SCRUB_LITERALS[@]:-}"; do
        [ "$_e" = "$_escaped" ] && return 0
    done

    _IGOR_SCRUB_LITERALS+=("$_escaped")
}

# ---------------------------------------------------------------------------
# igor_scrub_register_pattern <ere_pattern>
#
#   Register an ERE regex pattern for redaction.
#   The pattern is used verbatim in: sed -E "s|<pattern>|[REDACTED]|g"
# ---------------------------------------------------------------------------
igor_scrub_register_pattern() {
    local _pat="$1"
    [ -n "$_pat" ] || return 0

    # Dedup
    local _p
    for _p in "${_IGOR_SCRUB_PATTERNS[@]:-}"; do
        [ "$_p" = "$_pat" ] && return 0
    done

    _IGOR_SCRUB_PATTERNS+=("$_pat")
}

# ---------------------------------------------------------------------------
# igor_scrub <text>
#
#   Apply all registered literals and patterns to <text> and print the
#   scrubbed result on stdout.
#   Literals are applied first (exact matches), then ERE patterns.
# ---------------------------------------------------------------------------
igor_scrub() {
    local _text="$1"
    [ -n "$_text" ] || { printf '%s\n' "$_text"; return 0; }

    # ── Literal pass ──────────────────────────────────────────────────────
    local _lit
    for _lit in "${_IGOR_SCRUB_LITERALS[@]:-}"; do
        [ -n "$_lit" ] || continue
        _text=$(printf '%s\n' "$_text" | sed "s|${_lit}|[REDACTED]|g")
    done

    # ── Pattern pass ──────────────────────────────────────────────────────
    local _pat
    for _pat in "${_IGOR_SCRUB_PATTERNS[@]:-}"; do
        [ -n "$_pat" ] || continue
        _text=$(printf '%s\n' "$_text" | sed -E "s|${_pat}|[REDACTED]|g")
    done

    printf '%s\n' "$_text"
}

# ---------------------------------------------------------------------------
# _scrub_read_section_key <file> <section> <key>
#
#   Read the first value for <key> within [<section>] of an INI-style file.
# ---------------------------------------------------------------------------
_scrub_read_section_key() {
    local _file="$1" _section="$2" _key="$3"
    [ -f "$_file" ] || return 1
    awk -v section="[${_section}]" -v key="${_key}" '
        /^\[/ { in_section = ($0 == section) }
        in_section && $0 ~ ("^" key "[[:space:]]*=") {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit
        }
    ' "$_file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# igor_scrub_load_module_secrets <module_dir>
#
#   Read the [secrets] section from <module_dir>/module.conf and register:
#     variables=VAR1,VAR2   — look up each name in the current environment,
#                             register its value as a literal
#     scrub_patterns=P1,P2  — register each as an ERE pattern directly
# ---------------------------------------------------------------------------
igor_scrub_load_module_secrets() {
    local _dir="$1"
    local _conf="${_dir}/module.conf"
    [ -f "$_conf" ] || return 0

    # ── variables — look up current env values ─────────────────────────
    local _vars_raw _var
    _vars_raw=$(_scrub_read_section_key "$_conf" "secrets" "variables" 2>/dev/null || true)
    _vars_raw="${_vars_raw//,/ }"
    for _var in $_vars_raw; do
        _var="${_var// /}"
        [ -z "$_var" ] && continue
        local _val="${!_var:-}"
        [ -n "$_val" ] && igor_scrub_register_literal "$_val"
    done

    # ── scrub_patterns — register as ERE patterns ──────────────────────
    local _pats_raw _pat
    _pats_raw=$(_scrub_read_section_key "$_conf" "secrets" "scrub_patterns" 2>/dev/null || true)
    [ -z "$_pats_raw" ] && return 0
    while IFS= read -r _pat; do
        _pat="${_pat#"${_pat%%[![:space:]]*}"}"   # ltrim
        [ -n "$_pat" ] && igor_scrub_register_pattern "$_pat"
    done < <(printf '%s\n' "$_pats_raw" | tr ',' '\n')
}

# ---------------------------------------------------------------------------
# igor_scrub_load_secrets_dir [dir]
#
#   Scan every *.env file in <dir> (default: ${IGOR_DIR}/secrets/).
#   For each KEY=value line, register the value as a literal.
#   Handles bare and double-/single-quoted values.
# ---------------------------------------------------------------------------
igor_scrub_load_secrets_dir() {
    local _dir="${1:-${IGOR_DIR}/secrets}"
    [ -d "$_dir" ] || return 0

    local _file _line _val
    for _file in "${_dir}"/*.env; do
        [ -f "$_file" ] || continue
        while IFS= read -r _line; do
            # Skip comments and blank lines
            [[ "$_line" =~ ^[[:space:]]*# ]] && continue
            [[ "$_line" =~ ^[[:space:]]*$ ]] && continue
            [[ "$_line" =~ = ]]              || continue

            _val="${_line#*=}"

            # Strip surrounding double-quotes then single-quotes
            _val="${_val#\"}" ; _val="${_val%\"}"
            _val="${_val#\'}" ; _val="${_val%\'}"

            igor_scrub_register_literal "$_val"
        done < "$_file"
    done
}
