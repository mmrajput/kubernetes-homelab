#!/usr/bin/env bash
# explain-log.sh — paste a log snippet from Grafana/kubectl and get an AI explanation
#
# Usage:
#   Pipe a single line:    echo "level=error msg=..." | ./scripts/explain-log.sh
#   Paste interactively:   ./scripts/explain-log.sh        (paste, then Ctrl-D)
#   From a file:           ./scripts/explain-log.sh < /tmp/velero.log
#
# Overrides:
#   MODEL=qwen2.5:14b ./scripts/explain-log.sh
#   OLLAMA_URL=http://localhost:11434 ./scripts/explain-log.sh

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${MODEL:-${OLLAMA_MODEL:-qwen2.5:7b}}"
SYSTEM_PROMPT="You are a Kubernetes and DevOps expert. The user will paste log output from a Kubernetes workload or system component. Explain in plain English: (1) what the error or warning means, (2) what is most likely causing it, (3) concrete steps to resolve it. Reference the exact error messages. Suggest kubectl commands or config changes where appropriate. Be specific and concise."

# ── Check Ollama is reachable ─────────────────────────────────────────────────
if ! curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
    echo "Error: Ollama is not running at ${OLLAMA_URL}" >&2
    echo "Start it with: ollama serve" >&2
    exit 1
fi

# ── Read log input ────────────────────────────────────────────────────────────
if [ -t 0 ]; then
    echo "Paste the log output, then press Ctrl-D:"
    echo "---"
fi

LOG_INPUT="$(cat)"

if [ -z "$LOG_INPUT" ]; then
    echo "Error: no log input provided." >&2
    exit 1
fi

# ── Send to Ollama and stream response ───────────────────────────────────────
echo "" >&2
echo "Model: ${MODEL}" >&2
echo "---" >&2

PAYLOAD="$(jq -n \
    --arg model  "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user   "$LOG_INPUT" \
    '{
        model: $model,
        stream: true,
        messages: [
            { role: "system", content: $system },
            { role: "user",   content: ("Here is the log output:\n\n" + $user) }
        ]
    }')"

curl -sf --no-buffer \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${OLLAMA_URL}/v1/chat/completions" \
| while IFS= read -r line; do
    line="${line#data: }"
    [ -z "$line" ] || [ "$line" = "[DONE]" ] && continue
    printf '%s' "$(printf '%s' "$line" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)"
done

echo ""
