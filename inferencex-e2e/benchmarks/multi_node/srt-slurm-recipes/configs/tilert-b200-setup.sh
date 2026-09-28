#!/usr/bin/env bash
set -eo pipefail
source /infmax-workspace/benchmarks/benchmark_lib.sh --validation-only
check_env_vars TILERT_ROLE

case "$TILERT_ROLE" in
    prefill)
        python3 -m pip install --quiet --no-cache-dir --no-deps tilert==0.1.5.post3
        if ! python3 -c 'import nixl' 2>/dev/null; then
            python3 -m pip install --quiet --no-cache-dir nixl==1.3.1
        fi
        ;;
    decode|router)
        python3 -m pip install --quiet --no-cache-dir tilert==0.1.5.post3
        if ! python3 -c 'import uvicorn' 2>/dev/null; then
            python3 -m pip install --quiet --no-cache-dir fastapi uvicorn httpx
        fi
        if ! python3 -c 'import nixl' 2>/dev/null; then
            python3 -m pip install --quiet --no-cache-dir nixl==1.3.1
        fi
        if ! python3 -c 'from importlib.metadata import version; assert int(version("transformers").split(".")[0]) >= 5'; then
            python3 -m pip install --quiet --no-cache-dir 'transformers>=5.4.0'
        fi
        ;;
    *)
        echo "Unknown TileRT setup role: $TILERT_ROLE" >&2
        exit 1
        ;;
esac

if [[ "$TILERT_ROLE" == decode ]]; then
    # Keep the shared converted checkpoint reusable across allocations.
    mkdir -p /tilert_weights
    exec 9>/tilert_weights/.convert.lock
    flock -w 21600 9
    if [[ ! -f /tilert_weights/model.safetensors.index.json ]]; then
        python3 -m tilert.models.preprocess.weight_converter \
            --model_type glm-5 --model_dir /model --save_dir /tilert_weights
        test -f /tilert_weights/model.safetensors.index.json
    fi
    for file in /model/*; do
        [[ -f "$file" ]] || continue
        name="${file##*/}"
        [[ "$name" == *.safetensors || "$name" == model.safetensors.index.json ]] && continue
        [[ -e "/tilert_weights/$name" ]] || cp -p "$file" "/tilert_weights/$name"
    done
    test -f /tilert_weights/chat_template.jinja
    test -f /tilert_weights/tokenizer_config.json || test -f /tilert_weights/tokenizer.json
fi
