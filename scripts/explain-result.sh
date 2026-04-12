#!/usr/bin/env bash
# explain-result.sh — pick a k8sgpt Result CR and get an AI explanation from local Ollama
#
# Usage:
#   Interactive picker:    ./scripts/explain-result.sh
#   Explain by name:       ./scripts/explain-result.sh <result-name>
#   Explain all results:   ./scripts/explain-result.sh --all
#
# Overrides:
#   MODEL=qwen2.5:14b ./scripts/explain-result.sh
#   OLLAMA_URL=http://localhost:11434 ./scripts/explain-result.sh
#   K8SGPT_NS=k8sgpt ./scripts/explain-result.sh

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${MODEL:-${OLLAMA_MODEL:-qwen2.5:7b}}"
K8SGPT_NS="${K8SGPT_NS:-k8sgpt}"
SYSTEM_PROMPT="You are a Kubernetes and DevOps expert. The user will give you a k8sgpt Result CR describing a Kubernetes cluster issue. Explain: (1) what the problem is and why it occurs, (2) the likely root cause, (3) step-by-step remediation with exact kubectl commands or config changes. Be specific and actionable."

# ── Check prerequisites ───────────────────────────────────────────────────────
if ! curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
    echo "Error: Ollama is not running at ${OLLAMA_URL}" >&2
    echo "Start it with: ollama serve" >&2
    exit 1
fi

if ! kubectl get crd results.core.k8sgpt.ai >/dev/null 2>&1; then
    echo "Error: k8sgpt Result CRD not found. Is k8sgpt-operator installed?" >&2
    exit 1
fi

# ── Collect results ───────────────────────────────────────────────────────────
RESULTS="$(kubectl get results -n "${K8SGPT_NS}" --no-headers -o custom-columns='NAME:.metadata.name,KIND:.spec.kind,PARENT:.spec.parentObject' 2>/dev/null)"

if [ -z "$RESULTS" ]; then
    echo "No k8sgpt Result CRs found in namespace ${K8SGPT_NS}."
    echo "Results appear after the next analysis cycle (check: kubectl get k8sgpt -n ${K8SGPT_NS})."
    exit 0
fi

# ── Select result(s) ─────────────────────────────────────────────────────────
EXPLAIN_ALL=false
RESULT_NAME=""

if [ "${1:-}" = "--all" ]; then
    EXPLAIN_ALL=true
elif [ -n "${1:-}" ]; then
    RESULT_NAME="$1"
else
    # Interactive picker
    echo "Available k8sgpt Results:"
    echo ""
    echo "$RESULTS" | nl -ba -w3 -s ') '
    echo ""
    printf "Enter number (or 'a' for all): "
    read -r CHOICE

    if [ "$CHOICE" = "a" ]; then
        EXPLAIN_ALL=true
    else
        RESULT_NAME="$(echo "$RESULTS" | sed -n "${CHOICE}p" | awk '{print $1}')"
        if [ -z "$RESULT_NAME" ]; then
            echo "Invalid selection." >&2
            exit 1
        fi
    fi
fi

# ── Explain a single result ───────────────────────────────────────────────────
explain_result() {
    local name="$1"
    local raw
    raw="$(kubectl get result "${name}" -n "${K8SGPT_NS}" -o yaml 2>/dev/null)"

    if [ -z "$raw" ]; then
        echo "Result '${name}' not found." >&2
        return 1
    fi

    # Extract the useful fields: kind, parent, errors list
    local kind parent errors
    kind="$(echo "$raw" | kubectl get result "${name}" -n "${K8SGPT_NS}" \
        -o jsonpath='{.spec.kind}' 2>/dev/null)"
    parent="$(kubectl get result "${name}" -n "${K8SGPT_NS}" \
        -o jsonpath='{.spec.parentObject}' 2>/dev/null)"
    errors="$(kubectl get result "${name}" -n "${K8SGPT_NS}" \
        -o jsonpath='{range .spec.results[*]}{.error}{"\n"}{end}' 2>/dev/null)"

    local user_content
    user_content="$(cat <<EOF
k8sgpt Result: ${name}
Resource kind: ${kind}
Resource name: ${parent}

Issues found:
${errors}

Full CR:
${raw}
EOF
)"

    echo "" >&2
    echo "=== Explaining: ${name} (${kind}/${parent}) ===" >&2
    echo "Model: ${MODEL}" >&2
    echo "---" >&2

    PAYLOAD="$(jq -n \
        --arg model  "$MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg user   "$user_content" \
        '{
            model: $model,
            stream: true,
            messages: [
                { role: "system", content: $system },
                { role: "user",   content: $user }
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
    echo ""
}

# ── Run ───────────────────────────────────────────────────────────────────────
if [ "$EXPLAIN_ALL" = true ]; then
    while IFS= read -r line; do
        name="$(echo "$line" | awk '{print $1}')"
        [ -n "$name" ] && explain_result "$name"
    done <<< "$RESULTS"
else
    explain_result "$RESULT_NAME"
fi
