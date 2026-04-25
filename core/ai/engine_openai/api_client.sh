#!/bin/bash
# ==============================================================================
#  engine_openai/api_client.sh
#
#  Thin shim for OpenAI-native models.
#  Currently routes through OpenRouter's OpenAI-compatible endpoint.
#  NEXUS_PROVIDER must already be set before calling.
#
#  NEXUS_TOOLS_JSON is read by ai_engine.py and passed as the "tools" array
#  in the API payload, enabling native function calling.
# ==============================================================================

engine_make_api_call() {
    python3 "${IGOR_DIR}/core/ai/ai_engine.py" call
}
