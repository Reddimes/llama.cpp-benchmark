#!/bin/bash

# --- Configuration ---
MODEL_API_URL="${MODEL_API_URL:-http://127.0.0.1:8888/v1/models}"
DEFAULT_ITERATIONS=10
DEFAULT_OUTPUT_SIZE=1024
RESULTS_DIR="benchmark_logs"

# --- Functions ---

get_available_models() {
    models=$(curl -s "$MODEL_API_URL" | grep -oP '"id":"\K[^"]+')
    if [ -z "$models" ]; then
        echo ""
        return 1
    fi
    echo "$models"
}

print_header() {
    clear
    echo "========================================================================================================================================================================================"
    echo "                                     Master Benchmark Dashboard"
    echo "========================================================================================================================================================================================"
    printf "%-75s | %-12s | %-5s | %-10s | %-10s | %-10s | %-8s\n" "MODEL" "TASK" "ITER" "STATUS" "DUR(s)" "TPS" "TOKENS"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
}

# --- Main ---

mkdir -p "$RESULTS_DIR"

# --- MODEL SELECTION ---

mapfile -t model_list < <(get_available_models)

if [ ${#model_list[@]} -eq 0 ]; then
    echo "Error: Could not fetch models from $MODEL_API_URL"
    exit 1
fi

echo ""
echo "Available Models:"
for i in "${!model_list[@]}"; do
    echo "[$i] ${model_list[$i]}"
done
echo ""
read -p "Select model numbers (comma-separated, e.g., 0,2): " model_input
IFS=',' read -ra ADDR <<< "$model_input"
SELECTED_MODELS=()
for i in "${ADDR[@]}"; do
    idx=$(echo "$i" | xargs)
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "${#model_list[@]}" ]; then
        SELECTED_MODELS+=("${model_list[$idx]}")
    fi
done

if [ ${#SELECTED_MODELS[@]} -eq 0 ]; then
    echo "No valid models selected."
    exit 1
fi

# --- PARAMETERS ---
read -p "Enter iterations per model [$DEFAULT_ITERATIONS]: " iter_input
ITERATIONS=${iter_input:-$DEFAULT_ITERATIONS}

read -p "Enter target output size (tokens) [$DEFAULT_OUTPUT_SIZE]: " size_input
OUTPUT_SIZE=${size_input:-$DEFAULT_OUTPUT_SIZE}

echo ""
echo "Select Task Type:"
echo "[0] Coding"
echo "[1] Reasoning"
echo "[2] Creative"
echo "[3] Math"
echo "[4] All"
echo ""
read -p "Choice [4]: " task_choice
case $task_choice in
    0) TASK_TYPES=("coding") ;;
    1) TASK_TYPES=("reasoning") ;;
    2) TASK_TYPES=("creative") ;;
    3) TASK_TYPES=("math") ;;
    4) TASK_TYPES=("coding" "reasoning" "creative" "math") ;;
    *) TASK_TYPES=("coding" "reasoning" "creative" "math") ;;
esac

# --- INITIALIZE DASHBOARD ---

# Prepare temporary directory for status files
STATUS_BASE_DIR=$(mktemp -d)
trap 'rm -rf "$STATUS_BASE_DIR"; tput cnorm; echo' INT TERM EXIT

# Pre-calculate jobs and initialize the table
declare -a JOB_STATUS_FILES
declare -a JOB_DETAILS_FILES
declare -a JOB_NAMES
declare -a JOB_TASKS
declare -a JOB_ITERS
declare -a JOB_MODELS

job_count=0
for model in "${SELECTED_MODELS[@]}"; do
    for task in "${TASK_TYPES[@]}"; do
        for (( iter=1; iter<=ITERATIONS; iter++ )); do
            JOB_NAMES[$job_count]="$model"
            JOB_TASKS[$job_count]="$task"
            JOB_ITERS[$job_count]="$iter"
            JOB_MODELS[$job_count]="$model"
            
            job_id=$(printf "%04d" $job_count)
            JOB_STATUS_FILES[$job_count]="$STATUS_BASE_DIR/job_$job_id.status"
            JOB_DETAILS_FILES[$job_count]="$STATUS_BASE_DIR/job_$job_id.details"
            
            echo "QUEUED" > "${JOB_STATUS_FILES[$job_count]}"
            echo "---" > "${JOB_DETAILS_FILES[$job_count]}"
            
            ((job_count++))
        done
    done
done

tput civis
print_header

# Print the initial table (all QUEUED)
for (( i=0; i<job_count; i++ )); do
    printf "%-75s | %-12s | %-5s | %-10s | %-10s | %-10s | %-8s\n" "${JOB_MODELS[$i]}" "${JOB_TASKS[$i]}" "${JOB_ITERS[$i]}" "QUEUED" "---" "---" "---"
done
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

# --- EXECUTION ---

for (( i=0; i<job_count; i++ )); do
    # Update status to RUNNING
    echo "RUNNING" > "${JOB_STATUS_FILES[$i]}"
    echo "Starting..." > "${JOB_DETAILS_FILES[$i]}"
    
    # Update dashboard row
    tput cup $((i + 5)) 0
    printf "%-75s | %-12s | %-5s | %-10s | %-10s | %-10s | %-8s" "${JOB_MODELS[$i]}" "${JOB_TASKS[$i]}" "${JOB_ITERS[$i]}" "RUNNING" "---" "---" "---"
    
    # Execute the specialist script
    # We use --iters 1 because we are iterating in the master loop
    ./output_size_benchmark.sh \
        --model "${JOB_MODELS[$i]}" \
        --task-type "${JOB_TASKS[$i]}" \
        --iters 1 \
        --output-size "$OUTPUT_SIZE" \
        --status-file "${JOB_STATUS_FILES[$i]}" \
        --run-id "Master-$i" \
        > /dev/null 2>&1 # Suppress stdout/stderr entirely as status is in file
    
    # Parse details from the status file
    IFS='|' read -r STATUS DUR TPS TOKENS < "${JOB_STATUS_FILES[$i]}"
    
    # Format duration to 2 decimal places if it's a number
    if [[ "$DUR" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        DUR=$(printf "%.2f" "$DUR")
    fi
    
    # Parse details from the status file
    IFS='|' read -r STATUS DUR TPS TOKENS < "${JOB_STATUS_FILES[$i]}"
    
    # Format duration to 2 decimal places if it's a number
    if [[ "$DUR" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        DUR=$(printf "%.2f" "$DUR")
    fi

    # Update dashboard row
    tput cup $((i + 5)) 0
    printf "%-75s | %-12s | %-5s | %-10s | %-10s | %-10s | %-8s" "${JOB_MODELS[$i]}" "${JOB_TASKS[$i]}" "${JOB_ITERS[$i]}" "$STATUS" "$DUR" "$TPS" "$TOKENS"
done

# --- FINALIZATION ---

tput cup $((job_count + 5)) 0
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "All tasks complete."
echo "Results are stored in $RESULTS_DIR"
tput cnorm
echo ""
