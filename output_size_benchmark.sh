#!/bin/bash

# --- Configuration ---
URL="http://127.0.0.1:8888/v1/completions"
MODEL_API_URL="http://127.0.0.1:8888/v1/models"
MAX_TOKENS=1500
DEFAULT_ITERATIONS=2
DEFAULT_OUTPUT_SIZE=8192
HF_HUB_DIR="$HOME/.cache/huggingface/hub"
RESULTS_DIR="benchmark_logs"
RESULTS_CSV="$RESULTS_DIR/benchmark_results.csv"
TEMP=0

# --- Argument Parsing ---
SELECTED_MODEL=""
ITERATIONS=$DEFAULT_ITERATIONS
OUTPUT_SIZE=$DEFAULT_OUTPUT_SIZE
RUN_ID="0"
TASK_TYPE="none"
STATUS_FILE=""
SILENT=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --model) SELECTED_MODEL="$2"; shift ;;
        --iters) ITERATIONS="$2"; shift ;;
        --output-size) OUTPUT_SIZE="$2"; shift ;;
        --run-id) RUN_ID="$2"; shift ;;
        --task-type) TASK_TYPE="$2"; shift ;;
        --status-file) STATUS_FILE="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ -n "$STATUS_FILE" ]; then
    SILENT=true
fi

# --- Functions ---
get_clean_model_names() {
    if [ ! -d "$HF_HUB_DIR" ]; then
        echo ""
        return 1
    fi
    
    find "$HF_HUB_DIR" -maxdepth 1 -type d -name "models--*" | sort | while read -r dir; do
        base=$(basename "$dir")
        name=${base#models--}
        name=${name//--\/}
        echo "$name"
    done
}

load_model_if_unloaded() {
    local model_pattern="$1"
    echo "Checking status for model pattern: $model_pattern..."
    
    local models_json=$(curl -s "$MODEL_API_URL")
    
    # Find the full ID that matches the pattern
    local full_model_id=$(echo "$models_json" | grep -oP '"id":"\K[^"]+' | grep -F "$model_pattern" | head -n 1)

    if [ -z "$full_model_id" ]; then
        echo "Error: No model matching '$model_pattern' found in server."
        return 1
    fi

    echo "Matched full model ID: $full_model_id"
    
    # Get the status for the full ID
    local status=$(echo "$models_json" | grep -oP '"id":"\K[^"]+' | grep -A 10 "$full_model_id" | grep -oP '"value":"\K[^"]+')

    if [ "$status" == "unloaded" ]; then
        echo "Model is unloaded. Attempting to load..."
        curl -s -X POST "$URL" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$full_model_id\", \"prompt\": \"\", \"max_tokens\": 1}" > /dev/null
            
        local count=0
        while [ "$status" != "loaded" ] && [ $count -lt 15 ]; do
            sleep 2
            status=$(curl -s "$MODEL_API_URL" | grep -oP '"id":"\K[^"]+' | grep -A 10 "$full_model_id" | grep -oP '"value":"\K[^"]+')
            echo "Waiting for load... (Status: $status)"
            count=$((count + 1))
        done
        
        if [ "$status" != "loaded" ]; then
            echo "Error: Failed to load model $full_model_id after 30 seconds."
            return 1
        fi
        echo "Model $full_model_id loaded successfully."
    elif [ "$status" == "loaded" ]; then
        echo "Model $full_model_id is already loaded."
    else
        echo "Warning: Model $full_model_id status is '$status'. Proceeding..."
    fi
    
    # Export the full model ID for use in the rest of the script
    export SELECTED_MODEL="$full_model_id"
    return 0
}

select_model() {
    echo "Searching for models in $HF_HUB_DIR..."
    if [ ! -d "$HF_HUB_DIR" ]; then
        echo "Error: $HF_HUB_DIR does not exist."
        exit 1
    fi
    
    mapfile -t model_list < <(get_clean_model_names)
    if [ ${#model_list[@]} -eq 0 ]; then
        echo "No models found in $HF_HUB_DIR."
        exit 1
    fi
    
    echo ""
    echo "Available Models:"
    for i in "${!model_list[@]}"; do
        echo "[$i] ${model_list[$i]}"
    done
    echo ""
    read -p "Select a model number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt "${#model_list[@]}" ]; then
        SELECTED_MODEL="${model_list[$choice]}"
    else
        echo "Invalid selection."
        exit 1
    fi
    echo "Selected Model: $SELECTED_MODEL"
    echo "----------------------------------------------------------------"
}

select_iterations() {
    read -p "Enter number of iterations [ $DEFAULT_ITERATIONS ]: " choice
    ITERATIONS=${choice:-$DEFAULT_ITERATIONS}
    echo "Iterations set to: $ITERATIONS"
    echo "----------------------------------------------------------------"
}

select_output_size() {
    read -p "Enter target output size (tokens) [$DEFAULT_OUTPUT_SIZE]: " choice
    OUTPUT_SIZE=${choice:-$DEFAULT_OUTPUT_SIZE}
    echo "Target output size: $OUTPUT_SIZE tokens"
    echo "----------------------------------------------------------------"
}

select_task_type() {
    echo ""
    echo "Select Task Type:"
    echo "[0] Coding (Complex implementation)"
    echo "[1] Reasoning (Logic/Puzzles)"
    echo "[2] Creative (Storytelling/Poetry)"
    echo "[3] Math (Complex derivation)"
    echo ""
    read -p "Choice [0-3]: " choice
    case $choice in
        0) TASK_TYPE="coding" ;;
        1) TASK_TYPE="reasoning" ;;
        2) TASK_TYPE="creative" ;;
        3) TASK_TYPE="math" ;;
        *) TASK_TYPE="coding" ;;
    esac
    echo "Selected Type: $TASK_TYPE"
    echo "----------------------------------------------------------------"
}

get_prompt_for_task() {
    local type=$1
    local target_size=$2
    local base_prompt=""

    case $type in
        "coding") base_prompt="Write a robust, production-grade Python implementation of a complex data structure that handles all edge cases and includes unit tests. Ensure it is highly optimized. Aim for approximately $target_size tokens in your response. " ;;
        "reasoning") base_prompt="Solve this complex logical riddle step-by-step: A man is looking at a photograph of someone. His mother said, 'This man's father is my father's son.' Who is in the photograph? Provide a detailed, logical deduction of approximately $target_size tokens. " ;;
        "creative") base_prompt="Write a multi-chapter, highly descriptive, and immersive short story about a journey through a nebula of crystalline structures. The story should be structured into distinct parts: 1. The Arrival: Describe the approach to the nebula and the first visual contact. 2. The Exploration: Detail the discovery of various crystalline structures and the sensations of navigating them. 3. The Conflict: Describe a sudden cosmic storm or environmental hazard. 4. The Resolution: Provide a concluding reflection on the voyage. Focus heavily on sensory details and cosmic wonder. Aim to reach a total length of approximately $target_size tokens." ;;
        "math") base_prompt="Provide a detailed, step-by-step derivation and solution for the following complex mathematical problem: Find the integral of x^2 * e^x from 0 to infinity. Ensure the response is approximately $target_size tokens long. " ;;
        *) base_prompt="Tell me a detailed story about a journey through space that is approximately $target_size tokens long. " ;;
    esac
    echo "${base_prompt}"
}

[ "$SILENT" = false ] && print_header() {
    echo "==========================================================================================="
    echo " Task Performance Benchmark"
    echo " Model: $SELECTED_MODEL"
    echo " Task Type: $TASK_TYPE"
    echo " Run-ID: $RUN_ID"
    echo " Iterations: $ITERATIONS"
    echo " Target Output Size: $OUTPUT_SIZE tokens"
    echo "==========================================================================================="
    printf "%-10s | %-12s | %-15s | %-15s | %-10s | %-10s\n" "Iteration" "Task Type" "Output Size" "Total Time(s)" "Gen TPS" "Status"
    echo "-------------------------------------------------------------------------------------------"
}

log_to_csv() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$RUN_ID,$timestamp,$SELECTED_MODEL,$TASK_TYPE,$OUTPUT_SIZE,$1,$2,$3,$4,$5" >> "$RESULTS_CSV"
}

# --- Main ---

mkdir -p "$RESULTS_DIR"
if [ ! -f "$RESULTS_CSV" ]; then
    echo "Run-ID,Timestamp,Model,TaskType,OutputSize,Iteration,Tokens,Duration,TPS,Status" > "$RESULTS_CSV"
fi

if [ -z "$SELECTED_MODEL" ]; then
    select_model
fi
if [ "$TASK_TYPE" == "none" ]; then
    select_task_type
fi
if [ -z "$ITERATIONS" ]; then
    select_iterations
fi
if [ -z "$OUTPUT_SIZE" ]; then
    select_output_size
fi

if [ "$SILENT" = false ]; then
    load_model_if_unloaded "$SELECTED_MODEL" || exit 1
else
    load_model_if_unloaded "$SELECTED_MODEL" > /dev/null 2>&1 || true
fi

[ "$SILENT" = false ] && print_header

for (( iter=1; iter<=ITERATIONS; iter++ )); do
    PROMPT_TEXT=$(get_prompt_for_task "$TASK_TYPE" "$OUTPUT_SIZE")
    
    if [ "$SILENT" = true ]; then
        echo "$status" > "$STATUS_FILE"
    else
        printf "\r%-10s | %-12s | %-15s | %-15s | %-10s | %-10s" "$iter" "$TASK_TYPE" "$OUTPUT_SIZE" "-" "-" "RUNNING"
    fi
    
    start_time=$(date +%s.%N)
    response_file=$(mktemp)
    curl -s -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$SELECTED_MODEL\", \"prompt\": \"$PROMPT_TEXT\", \"max_tokens\": $OUTPUT_SIZE, \"temperature\": $TEMP}" > "$response_file"
    end_time=$(date +%s.%N)
    
    duration=$(echo "$end_time - $start_time" | bc)
    tokens=$(grep -oP '"completion_tokens":\s*\K\d+' "$response_file" || echo 0)
    
    status="DONE"
    tps="0.00"
    if [ "$tokens" -eq 0 ]; then
        status="FAILED"
    else
        tps=$(echo "scale=2; $tokens / $duration" | bc)
    fi
    rm "$response_file"
    
    if [ "$SILENT" = true ]; then
        if [ "$status" = "DONE" ]; then
            echo "SUCCESS|$duration|$tps|$tokens" > "$STATUS_FILE"
        else
            echo "FAILED|0|0|0" > "$STATUS_FILE"
        fi
    else
        printf "\r%-10s | %-12s | %-15s | %-15s | %-10s | %-10s" "$iter" "$TASK_TYPE" "$OUTPUT_SIZE" "$duration" "$tps" "$status"
    fi
    log_to_csv "$iter" "$tokens" "$duration" "$tps" "$status"
done

[ "$SILENT" = false ] && echo "-------------------------------------------------------------------------------------------"
[ "$SILENT" = false ] && echo "Benchmark Complete."
