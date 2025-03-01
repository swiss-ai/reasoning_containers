#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to display usage information
usage() {
    echo "Usage: $0 <command> <project_name>"
    echo ""
    echo "Commands:"
    echo "  remote <project_name> - Create a branch and set up the env for a project"
    echo "  build <project_name>  - Build the podman image for a project"
    echo "  local <project_name>  - Test the local image"
    echo ""
    echo "Example:"
    echo "  $0 remote reasoning:2025.1"
    exit 1
}

# Check if the number of arguments is correct
if [ $# -lt 2 ]; then
    echo "Error: Insufficient arguments provided."
    usage
fi

COMMAND=$1
PROJECT_NAME=$2
BASE_ENV="reasoning_base"
BASE_REPO_DIR="/capstor/store/cscs/swissai/a06/reasoning/imgs"
BRANCH_NAME="${PROJECT_NAME}_${USER}_$(date +"%y-%m-%d:%H-%M-%S")"
REPO_DIR="$SCRIPT_DIR"
EDF_DIR="$HOME/.edf"

# Determine if the project is a base environment or a regular project
if [ -d "$REPO_DIR/$PROJECT_NAME" ]; then
    # It's a base environment in the root directory
    IS_BASE=true
    PROJECT_DIR="$REPO_DIR/$PROJECT_NAME"
    echo "Using base environment at $PROJECT_DIR"
else
    # It's a regular project in the projects directory
    PROJECT_DIR="$REPO_DIR/projects/$PROJECT_NAME"
    IS_BASE=false
    echo "Using project directory at $PROJECT_DIR"
fi

# Function to create a new branch
create_branch() {
	if git rev-parse --verify --quiet "$BRANCH_NAME"; then
		git checkout "$BRANCH_NAME"
	else
		git checkout -b "$BRANCH_NAME"
		echo "Created branch: $BRANCH_NAME"
	fi
	echo "Checked out branch: $BRANCH_NAME"
    # Check if BASE_REPO_DIR exists and is a git repository
    if [ ! -d "$BASE_REPO_DIR/.git" ]; then
        echo "Warning: Base repository at $BASE_REPO_DIR is not a git repository or doesn't exist"
    else
        echo "Comparing with base repository at $BASE_REPO_DIR..."

        # Get the current branch
        local CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

        # Fetch the base repository HEAD
        local BASE_HEAD=$(cd "$BASE_REPO_DIR" && git rev-parse HEAD)

        # Check how many commits ahead/behind
        local AHEAD=$(git rev-list --count $BASE_HEAD..HEAD 2>/dev/null || echo "unknown")
        local BEHIND=$(git rev-list --count HEAD..$BASE_HEAD 2>/dev/null || echo "unknown")

        # Report status
        if [ "$AHEAD" != "unknown" ] && [ "$BEHIND" != "unknown" ]; then
            echo "Current branch $CURRENT_BRANCH::BaseHEAD: $AHEAD commit(s) ahead, $BEHIND commit(s) behind"
        else
            echo "Unable to determine ahead/behind count of current branch $CURRENT_BRANCH"
        fi
    fi
}

# Function to set up the environment
setup_environment() {
    # Create the EDF directory if it doesn't exist
    mkdir -p "$EDF_DIR"

    # Check if the project directory exists
    if [ ! -d "$PROJECT_DIR" ]; then
		echo "Project $PROJECT_NAME doesn't exist, creating it..."
		mkdir -p "$PROJECT_DIR"
		# Create basic Dockerfile that extends from reasoning_base
		cat > "$PROJECT_DIR/Dockerfile" << EOF
FROM $BASE_ENV

# Add your project-specific dependencies here
# RUN apt-get update && apt-get install python3-pip python3-venv -y

# Set working directory
WORKDIR /workspace

# Add entrypoint script if needed
# COPY entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh
# ENTRYPOINT ["/entrypoint.sh"]
EOF
		echo "Created template $PROJECT_DIR/Dockerfile"

		cat > "$PROJECT_DIR/env.toml" << EOF
base_environment = "$REPO_DIR/$BASE_ENV/env.toml"
mounts = ["/capstor", "/iopsstor", "/users"]
workdir = "/workspace"

[annotations]
com.hooks.aws_ofi_nccl.enabled = "true"
com.hooks.aws_ofi_nccl.variant = "cuda12"
EOF
		echo "Created template $PROJECT_DIR/env.toml"
    else
        echo "Using existing project at $PROJECT_DIR"
    fi
}

# Function to create the environment TOML file
launch_debug() {
    local use_local_img=$1

    if [ "$use_local_img" = "--use_local_img" ]; then
        # Check if image file exists
        if [ ! -f "$PROJECT_DIR/image.sqsh" ]; then
            echo "Error: Local image file not found at $PROJECT_DIR/image.sqsh"
            echo "Please build the image first using: $0 build $PROJECT_NAME"
            exit 1
        fi

        cat > "$EDF_DIR/$PROJECT_NAME.toml" << EOF
base_environment = "$PROJECT_DIR/env.toml"
image = "$PROJECT_DIR/image.sqsh"
workdir = "$HOME/scratch"
EOF
    else
        cat > "$EDF_DIR/$PROJECT_NAME.toml" << EOF
base_environment = "$PROJECT_DIR/env.toml"
workdir = "$HOME/scratch"
EOF
    fi

    echo "Created local environment file at $EDF_DIR/$PROJECT_NAME.toml"

    echo "Launching debug environment with sdebug..."
    sdebug --environment="$PROJECT_NAME" bash
}

# Function to build the podman image
build_image() {
    echo "Building podman image for $PROJECT_NAME..."

    # Check if the project directory exists
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "Error: Project directory $PROJECT_DIR does not exist"
        echo "Run '$0 remote $PROJECT_NAME' first to set up the project."
        exit 1
    fi
    # Check if Dockerfile exists
    if [ ! -f "$PROJECT_DIR/Dockerfile" ]; then
        echo "Error: Dockerfile not found at $PROJECT_DIR/Dockerfile"
        exit 1
    fi

    # Use the build_env.sh script to build the image
    if [ -f "$REPO_DIR/build_env.sh" ]; then
        sdebug bash -c "$REPO_DIR/build_env.sh '$PROJECT_NAME'"
    else
        echo "Error: build_env.sh script not found in $REPO_DIR"
        echo "Check the repository for the script and ensure it's in the repository main directory"
        exit 1
    fi
}

# Main logic based on the command
case "$COMMAND" in
    remote)
        create_branch
		setup_environment
        echo "Testing $PROJECT_NAME remotely..."
        launch_debug
        ;;
    build)
        build_image
        ;;
    local)
        echo "Testing $PROJECT_NAME locally..."
        launch_debug --use_local_img
        ;;
    *)
        echo "Error: Unknown command: $COMMAND"
        usage
        ;;
esac

exit 0
