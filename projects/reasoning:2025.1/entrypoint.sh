#!/bin/bash

# Set up reasoning-gym repository in $SCRATCH
R_GYM_DIR="$HOME/scratch/reasoning-gym"
cd "$R_GYM_DIR" || { echo "Failed to change directory to $R_GYM_DIR"; exit 1; }
if [ ! -d "$R_GYM_DIR" ]; then
    # Clone the repository if it doesn't exist
    git clone https://github.com/open-thought/reasoning-gym.git "$R_GYM_DIR" || { echo "Failed to clone Reasoning-Gym"; exit 1; }

    # Install the package in development mode
    pip install -e . || { echo "Failed to install packages for Reasoning-Gym"; exit 1; }
    # Install development dependencies
    pip install -r requirements-dev.txt || { echo "Failed to install dev dependencies for Reasoning-Gym"; exit 1; }
else
    # Fetch updates without merging
    git fetch || { echo "Warning: Failed to fetch Reasoning-Gym updates"; }

    # Check how many commits ahead/behind
    AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "unknown")
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "unknown")

    # Report status
    if [ "$AHEAD" != "unknown" ] && [ "$BEHIND" != "unknown" ]; then
        echo "Reasoning-Gym status local::origin/main: $AHEAD commit(s) ahead, $BEHIND commit(s) behind"
    else
        echo "Reasoning-Gym status local::origin/main: Unable to determine ahead/behind count"
    fi
fi

# Execute the command passed to docker run
exec "$@"
