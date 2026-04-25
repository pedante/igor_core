#!/bin/bash
# ==============================================================================
#  IGOR — core/lib/cloudflare_ips.sh
#  Canonical Cloudflare IPv4 CIDR list — single source of truth.
#
#  Usage (caller sets an array variable name, then sources this file):
#    IGOR_CF_IPS_VAR=my_array source core/lib/cloudflare_ips.sh
#  Or use the helper function:
#    igor_cf_ips_get my_array   # populates my_array with all CIDRs
#
#  Source: https://www.cloudflare.com/ips-v4  (last updated 2024)
# ==============================================================================

# ── igor_cf_ips_get <nameref-var> ─────────────────────────────────────────────
# Populates the named array with Cloudflare IPv4 CIDRs.
# Example:  igor_cf_ips_get cf_ranges
#           for ip in "${cf_ranges[@]}"; do ...; done
igor_cf_ips_get() {
    local -n _cf_out="$1"
    _cf_out=(
        "103.21.244.0/22"
        "103.22.200.0/22"
        "103.31.4.0/22"
        "104.16.0.0/13"
        "104.24.0.0/14"
        "108.162.192.0/18"
        "131.0.72.0/22"
        "141.101.64.0/18"
        "162.158.0.0/15"
        "172.64.0.0/13"
        "173.245.48.0/20"
        "188.114.96.0/20"
        "190.93.240.0/20"
        "197.234.240.0/22"
        "198.41.128.0/17"
    )
}
