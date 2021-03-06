#!/bin/bash

# ========== Experiment Idx. 20 / Seq. 20 / N. 4 - _S=20 D1_N=4 a=-1 b=-1 c=1 d=-1 e=-1 f=1 ==========\n\n'
set -u

# Prints header
echo -e '\n\n========== Experiment Idx. 20 / Seq. 20 / N. 4 - _S=20 D1_N=4 a=-1 b=-1 c=1 d=-1 e=-1 f=1 ==========\n\n'

# Prepares all environment variables
JBHI_DIR="$HOME/jbhi-special-issue"
DATASET_DIR="$JBHI_DIR/data/challenge-train-seg.598.tfr"
MODEL_DIR="$JBHI_DIR/models/deep.4"
OUTPUT_DIR="$MODEL_DIR"
# ...variables expected by jbhi-checks.include.sh and jbhi-footer.include.sh
SOURCES_GIT_DIR="$JBHI_DIR/jbhi-special-issue"
LIST_OF_INPUTS="$DATASET_DIR/finish.txt"
START_PATH="$OUTPUT_DIR/start.txt"
FINISH_PATH="$OUTPUT_DIR/finish.txt"
LOCK_PATH="$OUTPUT_DIR/running.lock"
LAST_OUTPUT="$OUTPUT_DIR/model.ckpt-30000.meta"
# EXPERIMENT_STATUS=1
# STARTED_BEFORE=No
mkdir -p "$MODEL_DIR"

#
# Assumes that the following environment variables where initialized
# SOURCES_GIT_DIR="$JBHI_DIR/jbhi-special-issue"
# LIST_OF_INPUTS="$DATASET_DIR/finish.txt:$MODELS_DIR/finish.txt:"
# START_PATH="$OUTPUT_DIR/start.txt"
# FINISH_PATH="$OUTPUT_DIR/finish.txt"
# LOCK_PATH="$OUTPUT_DIR/running.lock"
# LAST_OUTPUT="$MODEL_DIR/[[[:D1_MAX_NUMBER_OF_STEPS:]]].meta"
EXPERIMENT_STATUS=1
STARTED_BEFORE=No

# Checks if code is stable, otherwise alerts scheduler
pushd "$SOURCES_GIT_DIR" >/dev/null
GIT_STATUS=$(git status --porcelain)
GIT_COMMIT=$(git log | head -n 1)
popd >/dev/null
if [ "$GIT_STATUS" != "" ]; then
    echo 'FATAL: there are uncommitted changes in your git sources file' >&2
    echo '       for reproducibility, experiments only run on committed changes' >&2
    echo >&2
    echo '       Git status returned:'>&2
    echo "$GIT_STATUS" >&2
    exit 162
fi

# The experiment is already finished - exits with special code so scheduler won't retry
if [[ "$FINISH_PATH" != "-" ]]; then
    if [[ -e "$FINISH_PATH" ]]; then
        echo 'INFO: this experiment has already finished' >&2
        exit 163
    fi
fi

# The experiment is not ready to run due to dependencies - alerts scheduler
if [[ "$LIST_OF_INPUTS" != "" ]]; then
    IFS=':' tokens_of_input=( $LIST_OF_INPUTS )
    input_missing=No
    for input_to_check in ${tokens_of_input[*]}; do
        if [[ ! -e "$input_to_check" ]]; then
            echo "ERROR: input $input_to_check missing for this experiment" >&2
            input_missing=Yes
        fi
    done
    if [[ "$input_missing" != No ]]; then
        exit 164
    fi
fi

# Sets trap to return error code if script is interrupted before successful finish
LOCK_SUCCESS=No
FINISH_STATUS=161
function finish_trap {
    if [[ "$LOCK_SUCCESS" == "Yes" ]]; then
        rmdir "$LOCK_PATH" &> /dev/null
    fi
    if [[ "$FINISH_STATUS" == "165" ]]; then
        echo 'WARNING: experiment discontinued because other process holds its lock' >&2
    else
        if [[ "$FINISH_STATUS" == "160" ]]; then
            echo 'INFO: experiment finished successfully' >&2
        else
            [[ "$FINISH_PATH" != "-" ]] && rm -f "$FINISH_PATH"
            echo 'ERROR: an error occurred while executing the experiment' >&2
        fi
    fi
    exit "$FINISH_STATUS"
}
trap finish_trap EXIT


# While running, locks experiment so other parallel threads won't attempt to run it too
if mkdir "$LOCK_PATH" --mode=u=rwx,g=rx,o=rx &>/dev/null; then
    LOCK_SUCCESS=Yes
else
    echo 'WARNING: this experiment is already being executed elsewhere' >&2
    FINISH_STATUS="165"
    exit
fi

# If the experiment was started before, do any cleanup necessary
if [[ "$START_PATH" != "-" ]]; then
    if [[ -e "$START_PATH" ]]; then
        echo 'WARNING: this experiment is being restarted' >&2
        STARTED_BEFORE=Yes
    fi

    #...marks start
    date -u >> "$START_PATH"
    echo GIT "$GIT_COMMIT" >> "$START_PATH"
fi


# If the experiment was started before, do any cleanup necessary
if [[ "$STARTED_BEFORE" == "Yes" ]]; then
    echo -n
fi

#...starts training
python \
    "$SOURCES_GIT_DIR/train_image_classifier.py" \
    --model_name="resnet_v2_101_seg" \
    --max_number_of_steps="30000" \
    --optimizer=rmsprop \
    --dataset_name=skin_lesions \
    --task_name=label \
    --dataset_split_name=train \
    --preprocessing_name=dermatologic \
    --aggressive_augmentation="False" \
    --add_rotations="False" \
    --minimum_area_to_crop="0.05" \
    --normalize_per_image="0" \
    --save_interval_secs=3600 \
    --experiment_file="$MODEL_DIR/experiment.meta" \
    --experiment_tag="Factorial: 4; _S D1_N a b c d e f" \
    --dataset_dir="$DATASET_DIR" \
    --train_dir="$MODEL_DIR"
    # Tip: leave last the arguments that make the command fail if they're absent,
    # so if there's a typo or forgotten \ the entire thing fails
EXPERIMENT_STATUS="$?"

#    --checkpoint_path="$JBHI_DIR/running/resnet_v2_101.ckpt" \
#    --checkpoint_exclude_scopes="resnet_v2_101/logits" \
#    --ignore_missing_vars="True" \

#
#...starts training
if [[ "$EXPERIMENT_STATUS" == "0" ]]; then
    if [[ "$LAST_OUTPUT" == "" || -e "$LAST_OUTPUT" ]]; then
        if [[ "$FINISH_PATH" != "-" ]]; then
            date -u >> "$FINISH_PATH"
            echo GIT "$GIT_COMMIT" >> "$FINISH_PATH"
        fi
        FINISH_STATUS="160"
    fi
fi


