#!/bin/bash
# ==============================================================================
#  engine_anthropic/api_client.sh
#
#  Thin shim — delegates to ai_engine.py with provider=anthropic.
#  NEXUS_PROVIDER must already be set to "anthropic" before calling.
# ==============================================================================

engine_make_api_call() {
    python3 "${IGOR_DIR}/core/ai/ai_engine.py" call
}
