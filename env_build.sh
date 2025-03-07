#!/bin/bash
# env_build.sh - Global build script for envs
# Usage: ./env_build.sh <env_name>

set -eo pipefail

# Capture original directory and set trap to return on exit
ORIGINAL_DIR="$(pwd)"
trap "cd \"$ORIGINAL_DIR\"" EXIT

# Change to the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Function to list all available environments
list_available_environments() {
    echo -e "Available environments"
	echo -e "Base environment:\n\treasoning_base"
    if [ "$(ls -A projects/ 2>/dev/null)" ]; then
		echo "Projects:"
        ls -1 projects/ 2>/dev/null | sed 's/^/\t/'
    else
        echo "No project environments found"
    fi
}

# Check if environment name is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <env_name>"
    list_available_environments
    exit 1
fi

ENV_NAME="$1"
ENV_DIR=""

# Check if environment is in projects directory
if [ -d "projects/$ENV_NAME" ]; then
    ENV_DIR="projects/$ENV_NAME"
# Check if environment is a base environment in root directory
elif [ -d "$ENV_NAME" ]; then
    ENV_DIR="$ENV_NAME"
else
    echo "Error: Environment '$ENV_NAME' not found"
    list_available_environments
    exit 1
fi

# Check if Dockerfile exists
if [ ! -f "$ENV_DIR/Dockerfile" ]; then
    echo "Error: Dockerfile not found in $ENV_DIR"
    exit 1
fi

# Function to build an image and its dependencies recursively
build_image() {
    local dir_path="$1"
    local is_final_image="$2"  # Flag to indicate if this is the final image requested by the user
    local image_name=$(basename "$dir_path")

    echo "Analyzing Dockerfile: $dir_path/Dockerfile"

    # Check if Dockerfile exists in the directory
    if [ ! -f "$dir_path/Dockerfile" ]; then
        echo -e "\nError: Dockerfile not found at $dir_path/Dockerfile"
        exit 1
    fi

    # Extract all base images and stage names from the Dockerfile
    local base_images=()
    local stage_names=()
    declare -A stage_to_image

    while read -r line; do
        # Extract the base image name and stage name if present
        if [[ "$line" =~ ^FROM[[:space:]]+([^[:space:]]+)([[:space:]]+[Aa][Ss][[:space:]]+([^[:space:]]+))? ]]; then
            base_image="${BASH_REMATCH[1]}"
            if [[ -n "${BASH_REMATCH[3]}" ]]; then
                stage_name="${BASH_REMATCH[3]}"
                # Convert to lowercase for case-insensitive matching
                stage_name_lower=$(echo "$stage_name" | tr '[:upper:]' '[:lower:]')
                stage_names+=("$stage_name_lower")
                stage_to_image["$stage_name_lower"]="$base_image"
                echo -e "\tFound stage: $stage_name based on image: $base_image"
            fi

            # Resolve (nested) stage references
            base_image_lower=$(echo "$base_image" | tr '[:upper:]' '[:lower:]')
            while [[ " ${stage_names[@]} " =~ " $base_image_lower " ]]; do
                echo -e "\t\tNested stage reference detected: $base_image, resolving to: ${stage_to_image[$base_image_lower]}"
                base_image="${stage_to_image[$base_image_lower]}"
                base_image_lower=$(echo "$base_image" | tr '[:upper:]' '[:lower:]')
            done

            base_images+=("$base_image")
        fi
    done < <(grep "^FROM" "$dir_path/Dockerfile")

    # Remove duplicates from base_images
    base_images=($(echo "${base_images[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    echo -e "\tFound ${#base_images[@]} unique base image(s) in Dockerfile"

    # Process each base image
    for base_image in "${base_images[@]}"; do
        echo -e "\n\tProcessing base image: $base_image"

        # Skip special images like "scratch" which is a special Docker image
        if [[ "$base_image" == "scratch" ]]; then
            echo -e "\tSkipping special image: scratch (empty base image)"
            continue
        fi

        # Check if base image is a local image (not containing a registry URL)
        if [[ "$base_image" != *"/"* || "$base_image" == "localhost/"* ]]; then
            # Remove potential localhost/ prefix
            base_image=${base_image#localhost/}

            echo -e "\tFound local base image dependency: $base_image"

            # Check if we need to build the base image
            if ! podman image exists "$base_image"; then
                echo -e "\t\tBase image '$base_image' not found, attempting to build it first"

                # Look for the base image in the project structure
                if [ -d "projects/$base_image" ] && [ -f "projects/$base_image/Dockerfile" ]; then
                    # Recursively build the base image (not final)
                    build_image "projects/$base_image" "false"
                elif [ -d "$base_image" ] && [ -f "$base_image/Dockerfile" ]; then
                    # Try in root directory (for cases like reasoning_base) (not final)
                    build_image "$base_image" "false"
                else
                    echo -e "\nError: Could not find Dockerfile for base image '$base_image'"
                    echo -e "Called from $dir_path/Dockerfile"
                    exit 1
                fi
            else
                echo -e "\t\tBase image '$base_image' already exists"
            fi
        else
            echo -e "\tBase image '$base_image' is a remote image"
        fi
    done

    # Create a temporary build directory in the same location as the Dockerfile
    local tmp="tmp"
    local temp_dir="$dir_path/$tmp"
    rm -rf "$temp_dir" && mkdir -p "$temp_dir"

    # Copy Dockerfile to temp directory
    cp "$dir_path/Dockerfile" "$temp_dir/Dockerfile"

    # Copy entrypoint.sh if it exists
    if [ -f "$dir_path/entrypoint.sh" ]; then
        cp "$dir_path/entrypoint.sh" "$temp_dir/entrypoint.sh"
        # Ensure it's executable
        chmod +x "$temp_dir/entrypoint.sh"
    fi

    echo "Building image: $image_name"

    # Build with Podman (from the directory containing the Dockerfile)
    pushd "$dir_path" > /dev/null
    podman build -t "$image_name" "$tmp"

    # Only perform Enroot conversion and create TOML for the final image
    if [ "$is_final_image" = "true" ]; then
        # For Enroot format
        echo "Converting $image_name to Enroot format..."
        enroot_output=$(enroot import -o "./image.sqsh" "podman://$image_name" || true)
        echo "Enroot output: $enroot_output"

        # Create env.toml file
        echo "Creating env.toml file..."
        cat > "./env.toml" << EOF
image = "/capstor/store/cscs/swissai/a06/reasoning/imgs/$dir_path/image.sqsh"
mounts = ["/capstor", "/iopsstor", "/users"]
workdir = "/workspace"

[annotations]
com.hooks.aws_ofi_nccl.enabled = "true"
com.hooks.aws_ofi_nccl.variant = "cuda12"
EOF
        echo "Enroot conversion and TOML creation complete for final image: $image_name"
    else
        echo "Skipping Enroot conversion for intermediate image: $image_name"
    fi

    rm -rf "$tmp"

    popd > /dev/null

    echo "Build complete: $image_name"
}

# Start the build process with the final image flag set to true
build_image "$ENV_DIR" "true"
