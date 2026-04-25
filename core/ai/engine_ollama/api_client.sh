#!/bin/bash
# ==============================================================================
#  engine_ollama/api_client.sh
#
#  Thin shim — delegates to ai_engine.py with provider=ollama.
#  NEXUS_PROVIDER must already be set to "ollama" before calling.
# ==============================================================================

engine_make_api_call() {
    python3 "${IGOR_DIR}/core/ai/ai_engine.py" call
}
