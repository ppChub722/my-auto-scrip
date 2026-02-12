# load_scripts.sh
# ----------------------------------------------------
# Setup on a NEW PC (one-time):
#   1. Clone/copy this autoScript repo to the PC.
#   2. cp .env.local.example .env.local
#   3. Edit .env.local: set PROJECT_PATH_RSM_BE and PROJECT_PATH_RSM_FE to your repo paths.
#   4. source load_scripts.sh   (or add to your shell profile)
#   5. Run: deploy-dev-rsm-be  or  deploy-dev-rsm-fe
# ----------------------------------------------------
# 1. Load Local Paths from .env.local
# ----------------------------------------------------
# Get the folder where this file is located (works on any PC)
AUTO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$AUTO_ROOT/.env.local" ]; then
    source "$AUTO_ROOT/.env.local"
else
    echo "⚠️ Warning: .env.local not found."
    echo "   On a new PC: copy .env.local.example to .env.local and set PROJECT_PATH_RSM_BE and PROJECT_PATH_RSM_FE."
fi

# ----------------------------------------------------
# 2. Deployment Functions
# ----------------------------------------------------

deploy-dev-rsm-be() {
    echo "📂 Deploying RSM-BE..."
    # Uses PROJECT_PATH_RSM_BE from .env.local (same as deploy-rsm-be-dev.sh)
    bash "$AUTO_ROOT/deploy-rsm-be-dev.sh"
}

deploy-dev-rsm-fe() {
    echo "📂 Deploying RSM-FE..."
    # Uses PROJECT_PATH_RSM_FE from .env.local (same as deploy-rsm-fe-dev.sh)
    bash "$AUTO_ROOT/deploy-rsm-fe-dev.sh"
}