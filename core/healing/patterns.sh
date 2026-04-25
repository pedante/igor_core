#!/bin/bash
# ==============================================================================
#  IGOR — healing/patterns.sh
#  Pattern learning and suggestion system.
#
#  A "pattern" is a known symptom + fix pair, recorded when Igor successfully
#  resolves a problem. Patterns accumulate confirmation counts and can become
#  auto-eligible for hands-free repair after enough confirmations.
#
#  Provides:
#    pattern_record()          write a new pattern file
#    pattern_confirm()         increment CONFIRMED count on a pattern
#    pattern_fail()            increment FAILED count on a pattern
#    pattern_list()            list all pattern files with summary
#    pattern_suggest()         return FIX_CMD for a matching symptom code
#    pattern_eligible_check()  check if a pattern meets auto-eligible criteria
#    pattern_to_context()      format all patterns for AI system prompt injection
#
#  Pattern file format: plain KEY: VALUE pairs, one per line.
#  Location: ${IGOR_DIR}/data/patterns/{code}.pattern
#
#  Auto-eligible criteria (Stage 1 — data only, no auto-run in v1):
#    CONFIRMED >= 5, FAILED = 0, FIX_TIER is READ or CHANGE,
#    AUTO_ELIGIBLE: true must be set by the user explicitly.
# ==============================================================================

_PATTERNS_DIR="${IGOR_DIR}/data/patterns"

# ── Read a single field from a pattern file ───────────────────────────────────
_pattern_get_field() {
    local file="$1" field="$2"
    grep "^${field}: " "$file" 2>/dev/null | head -1 | sed "s/^${field}: //"
}

# ── Write or update a field in a pattern file ─────────────────────────────────
_pattern_set_field() {
    local file="$1" field="$2" value="$3"
    if grep -q "^${field}: " "$file" 2>/dev/null; then
        # Update existing
        local safe_val; safe_val=$(printf '%s' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^${field}: .*|${field}: ${safe_val}|" "$file"
    else
        # Append new field
        echo "${field}: ${value}" >> "$file"
    fi
}

# ── Record a new pattern ──────────────────────────────────────────────────────
# $1 = symptom_code     unique identifier, e.g. "app_down"
# $2 = description      human-readable description
# $3 = fix_tier         READ | CHANGE | DESTROY
# $4 = fix_cmd          command to run (for AI suggestion, not auto-run in v1)
# $5 = symptom_text     optional: what the check reported
pattern_record() {
    local code="$1" description="$2" fix_tier="$3" fix_cmd="$4" symptom_text="${5:-}"
    [ -z "$code" ] || [ -z "$fix_cmd" ] && return 1

    mkdir -p "$_PATTERNS_DIR"
    local file="${_PATTERNS_DIR}/${code}.pattern"
    local now; now=$(date '+%Y-%m-%d %H:%M:%S')

    # Guard against unbounded pattern file accumulation
    if declare -f igor_check_limit &>/dev/null && [ ! -f "$file" ]; then
        local _pf_count; _pf_count=$(find "$_PATTERNS_DIR" -name "*.pattern" -maxdepth 1 2>/dev/null | wc -l)
        igor_check_limit "max_pattern_files" "$_pf_count" 2>/dev/null || \
            warn "Pattern file limit reached (${_pf_count}) — review patterns in ${_PATTERNS_DIR}"
    fi

    if [ -f "$file" ]; then
        # Pattern already exists — update LAST_SEEN only
        _pattern_set_field "$file" "LAST_SEEN" "$now"
        return 0
    fi

    cat > "$file" << EOF
NAME: ${code}
DESCRIPTION: ${description}
SYMPTOM_CODE: ${code}
SYMPTOM_TEXT: ${symptom_text}
FIX_TIER: ${fix_tier}
FIX_CMD: ${fix_cmd}
CONFIRMED: 0
FAILED: 0
AUTO_ELIGIBLE: false
CREATED: ${now}
LAST_SEEN: ${now}
EOF
}

# ── Increment CONFIRMED count ─────────────────────────────────────────────────
pattern_confirm() {
    local code="$1"
    local file="${_PATTERNS_DIR}/${code}.pattern"
    [ ! -f "$file" ] && return 1

    local current; current=$(_pattern_get_field "$file" "CONFIRMED")
    current=$(( ${current:-0} + 1 ))
    _pattern_set_field "$file" "CONFIRMED" "$current"
    _pattern_set_field "$file" "LAST_SEEN" "$(date '+%Y-%m-%d %H:%M:%S')"
}

# ── Increment FAILED count ────────────────────────────────────────────────────
pattern_fail() {
    local code="$1"
    local file="${_PATTERNS_DIR}/${code}.pattern"
    [ ! -f "$file" ] && return 1

    local current; current=$(_pattern_get_field "$file" "FAILED")
    current=$(( ${current:-0} + 1 ))
    _pattern_set_field "$file" "FAILED" "$current"
}

# ── List all patterns ─────────────────────────────────────────────────────────
pattern_list() {
    [ ! -d "$_PATTERNS_DIR" ] && { info "No patterns recorded yet."; return 0; }

    local count=0
    for f in "${_PATTERNS_DIR}"/*.pattern; do
        [ -f "$f" ] || continue
        local name confirmed failed tier eligible
        name=$(_pattern_get_field "$f" "NAME")
        confirmed=$(_pattern_get_field "$f" "CONFIRMED")
        failed=$(_pattern_get_field "$f" "FAILED")
        tier=$(_pattern_get_field "$f" "FIX_TIER")
        eligible=$(_pattern_get_field "$f" "AUTO_ELIGIBLE")
        printf '  %-30s  confirmed:%-4s  failed:%-4s  tier:%-8s  auto:%s\n' \
            "$name" "${confirmed:-0}" "${failed:-0}" "${tier:-?}" "${eligible:-false}"
        (( count++ ))
    done
    [ $count -eq 0 ] && info "No patterns recorded yet."
}

# ── Suggest a fix for a symptom code ─────────────────────────────────────────
# Echoes FIX_CMD and FIX_TIER to stdout if a matching pattern exists.
# Returns 0 on match, 1 if no pattern found.
pattern_suggest() {
    local code="$1"
    local file="${_PATTERNS_DIR}/${code}.pattern"
    [ ! -f "$file" ] && return 1

    local fix_cmd fix_tier
    fix_cmd=$(_pattern_get_field "$file" "FIX_CMD")
    fix_tier=$(_pattern_get_field "$file" "FIX_TIER")
    [ -z "$fix_cmd" ] && return 1

    echo "FIX_TIER: ${fix_tier}"
    echo "FIX_CMD: ${fix_cmd}"
    return 0
}

# ── Check auto-eligibility criteria ──────────────────────────────────────────
# Stage 1 (current): data-collection only. This function validates criteria but
# there is NO code path that auto-executes a fix — that is Stage 2 (not yet
# implemented). Setting AUTO_ELIGIBLE: true in a pattern file has no effect in
# v1. It is reserved for the future self-healing executor.
# Returns 0 if pattern meets auto-eligible criteria (user still must set flag).
# Returns 1 if not eligible.
pattern_eligible_check() {
    local code="$1"
    local file="${_PATTERNS_DIR}/${code}.pattern"
    [ ! -f "$file" ] && return 1

    local confirmed failed tier
    confirmed=$(_pattern_get_field "$file" "CONFIRMED")
    failed=$(_pattern_get_field "$file" "FAILED")
    tier=$(_pattern_get_field "$file" "FIX_TIER")

    [ "${confirmed:-0}" -ge 5 ] || return 1
    [ "${failed:-0}" -eq 0 ]    || return 1
    [[ "$tier" == "READ" || "$tier" == "CHANGE" ]] || return 1
    return 0
}

# ── Format patterns for AI injection ─────────────────────────────────────────
# Outputs a structured text block of all known patterns for the system prompt.
pattern_to_context() {
    [ ! -d "$_PATTERNS_DIR" ] && return 0

    local count=0
    for f in "${_PATTERNS_DIR}"/*.pattern; do
        [ -f "$f" ] || continue
        (( count++ ))
    done
    [ $count -eq 0 ] && return 0

    echo ""
    echo "=== KNOWN REPAIR PATTERNS ==="
    echo "Igor has recorded $count known patterns from past fixes."
    echo ""

    for f in "${_PATTERNS_DIR}"/*.pattern; do
        [ -f "$f" ] || continue
        local name desc code tier cmd confirmed failed eligible
        name=$(_pattern_get_field "$f" "NAME")
        desc=$(_pattern_get_field "$f" "DESCRIPTION")
        code=$(_pattern_get_field "$f" "SYMPTOM_CODE")
        tier=$(_pattern_get_field "$f" "FIX_TIER")
        cmd=$(_pattern_get_field "$f" "FIX_CMD")
        confirmed=$(_pattern_get_field "$f" "CONFIRMED")
        failed=$(_pattern_get_field "$f" "FAILED")

        printf 'PATTERN: %s\n  %s\n  Confirmed: %s  Failed: %s  Tier: %s\n  Fix: %s\n\n' \
            "$name" \
            "${desc:-no description}" \
            "${confirmed:-0}" "${failed:-0}" "${tier:-?}" \
            "${cmd:-unknown}"
    done
    echo "=== END PATTERNS ==="
}
