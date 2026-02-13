#!/bin/bash

# --- 1. DYNAMIC PATH LOADING ---
# Find where this script is stored to locate the .env.local file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env.local" ]; then
    source "$SCRIPT_DIR/.env.local"
else
    echo "❌ Error: .env.local missing in $SCRIPT_DIR"
    exit 1
fi

# --- 2. CONFIGURATION ---
# Use the FE path from .env.local (set per PC)
PROJECT_PATH="$PROJECT_PATH_RSM_FE"

cd "$PROJECT_PATH" || { echo "❌ Cannot find project path: $PROJECT_PATH"; exit 1; }

echo "📂 Working directory: $(pwd)"

# BRANCH DEFINITIONS
LOCAL_BRANCH="feature/procurementV2-local"
MAIN_FEATURE_BRANCH="feature/procurementV2-integration"
ON_DEV_BRANCH="feature/procurementV2-onDev"
DEVELOP_BRANCH="develop"

# 🔍 AUTO IGNORE SETTINGS
AUTO_IGNORE_KEYWORD="local commit"

# ⛔ IGNORE LIST (external file in autoScript repo)
IGNORE_LIST_FILE="$SCRIPT_DIR/ignore-list-fe.txt"
IGNORE_LIST=""
if [ -f "$IGNORE_LIST_FILE" ]; then
    IGNORE_LIST=$(grep -v '^#' "$IGNORE_LIST_FILE" | grep -v '^$' || true)
fi
# =================================================

stop_on_error() {
    if [ $? -ne 0 ]; then
        echo "⛔ ERROR: $1"
        exit 1
    fi
}

# ---------------------------------------------------------
# STEP 0: SCAN, IDENTIFY & FILTER
# ---------------------------------------------------------
echo "🚀 Starting Deployment Process..."
echo "=== STEP 0: Scanning for New Features ==="

# Fetch to ensure we compare against latest server state
git fetch origin

declare -a RAW_HASHES
declare -a RAW_MSGS
declare -a JUNK_HASHES
RAW_COUNT=0
JUNK_COUNT=0

# 1. INITIAL SCAN (Get everything not manually ignored yet)
while read -r SIGN HASH MSG; do
    if [ "$SIGN" == "+" ]; then
        
        # Check Manual Ignore List
        if echo "$IGNORE_LIST" | grep -Fq "$HASH"; then continue; fi

        # Check Duplicates (Already on Integration)
        MSG_EXISTS=$(git log origin/$MAIN_FEATURE_BRANCH --fixed-strings --grep="$MSG" --format="%h")
        if [ -n "$MSG_EXISTS" ]; then continue; fi

        # Store in Raw Array
        RAW_HASHES[$RAW_COUNT]=$HASH
        RAW_MSGS[$RAW_COUNT]=$MSG
        
        # Check if it looks like Junk (Local Commit)
        if [[ "$MSG" == *"$AUTO_IGNORE_KEYWORD"* ]]; then
            JUNK_HASHES[$JUNK_COUNT]=$HASH
            ((JUNK_COUNT++))
        fi
        
        ((RAW_COUNT++))
    fi
done < <(git cherry -v origin/$MAIN_FEATURE_BRANCH origin/$LOCAL_BRANCH)

# --- DISPLAY & HIGHLIGHT PHASE ---
if [ $RAW_COUNT -eq 0 ]; then
    echo "✅ No new commits to deploy."
    exit 0
fi

echo ""
echo "🔎 SCAN RESULTS ($RAW_COUNT commits found):"
echo "---------------------------------------------------"
for (( i=0; i<$RAW_COUNT; i++ )); do
    H=${RAW_HASHES[$i]}
    M=${RAW_MSGS[$i]}
    
    # Check if this specific hash is in our junk pile
    IS_JUNK=0
    if [[ "$M" == *"$AUTO_IGNORE_KEYWORD"* ]]; then IS_JUNK=1; fi

    if [ $IS_JUNK -eq 1 ]; then
        # Highlight Junk in Yellow/Red
        echo -e "   ⚠️  \033[0;33m$H\033[0m | $M \033[0;31m(DETECTED LOCAL COMMIT)\033[0m"
    else
        # Standard Green for Good Commits
        echo -e "   ✅ \033[0;32m$H\033[0m | $M"
    fi
done
echo "---------------------------------------------------"

# --- BATCH IGNORE INTERVENTION ---
if [ $JUNK_COUNT -gt 0 ]; then
    echo ""
    read -p "🗑️  I found $JUNK_COUNT local commit(s). Do you want to add them to the ignore list? (y/N): " IGNORE_ACTION < /dev/tty
    
    if [[ "$IGNORE_ACTION" =~ ^[Yy]$ ]]; then
        echo "   ...Updating Ignore List..."
        for J_HASH in "${JUNK_HASHES[@]}"; do
            echo "$J_HASH" >> "$IGNORE_LIST_FILE"
            IGNORE_LIST="$IGNORE_LIST $J_HASH"
        done
        echo "   ✅ Updated. Re-calculating queue..."
        # Commit and push ignore-list file in autoScript repo
        (cd "$SCRIPT_DIR" && git add "$(basename "$IGNORE_LIST_FILE")" && git commit -m "chore: add local commits to ignore list" && git push origin) && echo "   📤 Ignore list committed and pushed to origin." || echo "   ⚠️ Could not commit/push (check autoScript repo)."
    else
        echo "   👌 Keeping them in deployment queue."
    fi
fi

# ---------------------------------------------------------
# BUILD FINAL DEPLOYMENT QUEUE (Re-Scan logic)
# ---------------------------------------------------------
declare -a FINAL_HASHES
declare -a FINAL_MSGS
FINAL_COUNT=0

for (( i=0; i<$RAW_COUNT; i++ )); do
    H=${RAW_HASHES[$i]}
    M=${RAW_MSGS[$i]}

    # Check against the (potentially updated) IGNORE_LIST
    if echo "$IGNORE_LIST" | grep -Fq "$H"; then 
        continue # Skip it, it was just ignored
    fi

    FINAL_HASHES[$FINAL_COUNT]=$H
    FINAL_MSGS[$FINAL_COUNT]=$M
    ((FINAL_COUNT++))
done

# --- FINAL CONFIRMATION ---
if [ $FINAL_COUNT -eq 0 ]; then
    echo ""
    echo "✅ No commits to deploy."
    exit 0
fi

echo ""
echo "📋 FINAL DEPLOYMENT LIST ($FINAL_COUNT commits):"
echo "---------------------------------------------------"
for (( i=0; i<$FINAL_COUNT; i++ )); do
    echo -e "   🚀 \033[0;32m${FINAL_HASHES[$i]}\033[0m | ${FINAL_MSGS[$i]}"
done
echo "---------------------------------------------------"

echo ""
read -p "❓ Proceed to deploy these $FINAL_COUNT commit(s)? (y/N): " DECISION < /dev/tty
if [[ ! "$DECISION" =~ ^[Yy]$ ]]; then
    echo "❌ Deployment Cancelled."
    exit 0
fi

# ---------------------------------------------------------
# HELPER: PROCESS & PUSH
# ---------------------------------------------------------
function process_and_push {
    TARGET=$1
    echo ""
    echo "=== Processing Branch: $TARGET ==="
    
    # 1. CLEAN
    git checkout $TARGET
    git reset --hard origin/$TARGET
    stop_on_error "Reset failed for $TARGET"

    # 2. CHERRY PICK LOOP
    for (( i=0; i<$FINAL_COUNT; i++ )); do
        HASH=${FINAL_HASHES[$i]}
        MSG=${FINAL_MSGS[$i]}

        echo -n "   Commit $((i+1))/$FINAL_COUNT: "

        # Safety Check: Does target already have this message?
        MSG_EXISTS=$(git log $TARGET --fixed-strings --grep="$MSG" --format="%h")

        if [ -n "$MSG_EXISTS" ]; then
            echo "⏭️  SKIP (Already exists)"
        else
            git cherry-pick $HASH
            if [ $? -ne 0 ]; then
                echo "💥 CONFLICT at $HASH. Script stopped."
                exit 1
            fi
            echo "✅ PICKED ($HASH)"
        fi
    done

    # PUSH TO ORIGIN
    echo "⬆️  Pushing $TARGET to origin..."
    git push origin $TARGET
    stop_on_error "Failed to push $TARGET"
    echo "✅ $TARGET Pushed Successfully."
}

# ---------------------------------------------------------
# EXECUTION
# ---------------------------------------------------------

# STEP 1: INTEGRATION
process_and_push $MAIN_FEATURE_BRANCH

# STEP 2: onDEV
process_and_push $ON_DEV_BRANCH

# STEP 3: DEVELOP (MERGE & CONFIRM PUSH)
echo ""
echo "=== STEP 3: Merge to Develop ==="
git checkout $DEVELOP_BRANCH
git pull origin $DEVELOP_BRANCH
stop_on_error "Update Develop Failed"

echo "🔀 Merging $ON_DEV_BRANCH -> $DEVELOP_BRANCH..."
git merge $ON_DEV_BRANCH --no-edit
if [ $? -ne 0 ]; then
    echo "💥 CONFLICT during Merge to Develop. Script stopped."
    exit 1
fi

# SHOW OUTGOING & CONFIRM
OUTGOING=$(git log origin/$DEVELOP_BRANCH..HEAD --oneline --graph --decorate --color=always)

echo ""
echo "========================================================"
echo "👀 READY TO PUSH TO '$DEVELOP_BRANCH':"
echo "========================================================"
echo -e "$OUTGOING"
echo "========================================================"

read -p "❓ Confirm push to origin/$DEVELOP_BRANCH? (y/N): " CONFIRM < /dev/tty
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    git push origin $DEVELOP_BRANCH
    stop_on_error "Push Failed"
    echo "🚀 Develop Pushed Successfully!"
else
    echo "⚠️  Push skipped (Merge is kept locally)."
fi

echo "🎉 Done! Back to $LOCAL_BRANCH"
git checkout $LOCAL_BRANCH