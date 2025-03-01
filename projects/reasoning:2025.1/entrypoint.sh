#!/bin/bash

# Setup the repositories
setup_repos() {
    local BASE_DIR="$HOME/scratch/dev"

    # Set up reasoning-gym repository in $SCRATCH
    # https://github.com/open-thought/reasoning-gym/blob/main/CONTRIBUTING.md
    local R_GYM_DIR="$BASE_DIR/reasoning-gym"
    if [ ! -d "$R_GYM_DIR" ]; then
        # Clone the repository if it doesn't exist
        git clone https://github.com/open-thought/reasoning-gym.git "$R_GYM_DIR" || { echo "Failed to clone Reasoning-Gym"; exit 1; }
        cd "$R_GYM_DIR" || { echo "Failed to change to Reasoning-Gym directory"; exit 1; }

        # Install the package in development mode
        pip install -e . || { echo "Failed to install packages for Reasoning-Gym"; exit 1; }
        # Install development dependencies
        pip install -r requirements-dev.txt || { echo "Failed to install dev dependencies for Reasoning-Gym"; exit 1; }
    else
        # Fetch updates without merging
        cd "$R_GYM_DIR" || { echo "Failed to change to Reasoning-Gym directory"; exit 1; }
        git fetch || { echo "Warning: Failed to fetch Reasoning-Gym updates"; }

        # Check how many commits ahead/behind
        local AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "unknown")
        local BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "unknown")

        # Report status
        if [ "$AHEAD" != "unknown" ] && [ "$BEHIND" != "unknown" ]; then
            echo "Reasoning-Gym status local::origin/main: $AHEAD commit(s) ahead, $BEHIND commit(s) behind"
        else
            echo "Reasoning-Gym status local::origin/main: Unable to determine ahead/behind count"
        fi
    fi
}


setup_repos

# Execute the command passed to docker run
exec "$@"
