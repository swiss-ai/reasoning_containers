# Reasoning Containers

This workflow uses Git for version control of Dockerfiles while keeping the actual built images (.sqsh files) excluded from version control using `.gitignore` mirror https://github.com/swiss-ai/reasoning_containers
- Team members propose changes through PRs via branches
- Administrators maintain control over official images on Clariden and scripts on GitHub:main

## Directory Structure

```
/capstor/store/cscs/swissai/a06/reasoning/imgs/  # Git repository
├── .git/                  # Git repository metadata
├── .gitignore             # Excludes *.sqsh files, *.log, and tmp/
├── env_build.sh           # Global build script for environments
├── env_update.sh          # Script for managing project environments
│
├── reasoning_base/        # Base image
│   ├── Dockerfile         # Base Dockerfile                                  (version controlled)
│   ├── image.sqsh         # Built image                          (generated)        (not tracked)
│   └── env.toml           # Environment configuration            (generated) (version controlled)
└── projects/              # Project-specific images
    ├── reasoning:latest/  # Latest reasoning project -> points to other project
    ├── reasoning:2025.1/  # Reasoning project version 2025.1
    │   ├── Dockerfile     # Project-specific Dockerfile                      (version controlled)
    │   ├── entrypoint.sh  # Project-specific entrypoint script               (version controlled)
    │   ├── image.sqsh     # Built image                          (generated)        (not tracked)
    │   └── env.toml       # Environment configuration            (generated) (version controlled)
    └── ...                # Other projects
```

## Git Repository Setup

1. **Repository Structure**:
   - The entire `imgs` directory is a Git repository
   - Only administrators have write access to the main branch
   - Team members can create branches and submit PRs

2. **Local Clariden Access Control**:
   - Administrators: write access to base `imgs`
   - Team members: read access to base, write access to their own local clones

3. **Git Ignore**:
   - The `.gitignore` file excludes built images and temporary files:
     ```
     *.sqsh
     *.log
     **/tmp/
     ```

## Editing Containers

First read _'Building a Container'_ https://github.com/swiss-ai/reasoning_getting-started

### Testing Modified Containers with `env_update.sh`

If you want to add or change versions of any dependencies in a container, follow these steps:

1. Clone the local repo to your `$SCRATCH`
   ```bash
   cd $SCRATCH
   git clone /capstor/store/cscs/swissai/a06/reasoning/imgs
   cd imgs
   ```

2. Set the project name environment variable (e.g., `reasoning:2025.1`)
   ```bash
   export PROJECT_NAME="<PROJECT>"
   ```

3. Check the original files of the container you want to edit:
   - `./projects/$PROJECT_NAME/Dockerfile`
   - `./projects/$PROJECT_NAME/entrypoint.sh` if applicable

4. Run the `env_update.sh` script to create a branch and set up the environment
   ```bash
   ./env_update.sh remote "$PROJECT_NAME"
   ```
   - A branch will be created `<PROJECT_NAME>_<USER>_<DATE_TIME>`
   - If the project exists:
     - Local `~/.edf/<PROJECT_NAME>.toml` will extend `$PROJECT_NAME/env.toml` by updating
     ```toml
     base_environment = "<PROJECT_NAME_DIR>/env.toml" # Updated by env_update.sh
     ...
     ```
   - If the project doesn't exist:
     - Creates project directory `./projects/$PROJECT_NAME` with template Dockerfile extending `reasoning_base/Dockerfile` by adding
     ```dockerfile
     FROM reasoning_base # Updated by env_update.sh
     ...
     ```
     - Local `~/.edf/<PROJECT_NAME>.toml` will extend `$PROJECT_NAME/env.toml` which preliminarily extends `reasoning_base/env.toml` until the image is built (see above '_base_environment_')
   - Updates `workdir = "$HOME/scratch"` in local `~/.edf/<PROJECT_NAME>.toml`

   A debug job will instantiate with the env `sdebug --environment="$PROJECT_NAME" bash` resolving to `~/.edf/<PROJECT_NAME>.toml`

5. In the debug compute node, install the dependencies you want to add or update (make sure to document+versions)

6. Test there is no compatibility issues with test-suites in our codebase

7. If everything works, you can try to build the container
   1. Exit the debug compute node `ctrl+d`
   2. Edit the `./projects/$PROJECT_NAME/Dockerfile` and `./projects/$PROJECT_NAME/entrypoint.sh` (if applicable)
   3. Build the image locally (you can also run `sdebug bash -c "$SCRATCH/imgs/env_build.sh '$PROJECT_NAME'"`)
   ```bash
   ./env_update.sh build "$PROJECT_NAME"
   ```
   This will submit a job to build the image. You can monitor the progress with:
   ```bash
   watch -n 10 "squeue --me"
   ```

8. If built successfully, instantiate a container with the env
   ```bash
   ./env_update.sh local "$PROJECT_NAME"
   ```
   This will launch a debug environment using your locally built image

9. Once it loads the debug compute node, test there is no compatibility issues with test-suites in our codebase

10. If it works, you can add, commit, and push your changes then create a PR
      ```bash
      cd $SCRATCH/imgs && git add . && git commit -m "Add your commit message here" && git push origin HEAD
      unset PROJECT_NAME
      ```

### Manually Building Containers with `env_build.sh`

`env_update.sh` should handle mose of your needs, if you need more low-level control over the environment files you can run `env_build.sh` directly on a compute node (to avoid slowing down the login node)

```bash
sdebug bash -c "$SCRATCH/imgs/env_build.sh '<PROJECT_NAME>'"
```
1. Analyzes the Dockerfile to identify base image dependencies
2. Recursively builds any local base images that don't exist (including stages)
3. Builds the target image
4. Converts the image to Enroot format (.sqsh)
5. Creates an env.toml file for the environment
   ```toml
   image = "/capstor/store/cscs/swissai/a06/reasoning/imgs/<project_path>/image.sqsh"
   mounts = ["/capstor", "/iopsstor", "/users"]
   workdir = "/workspace"

   [annotations]
   com.hooks.aws_ofi_nccl.enabled = "true"
   com.hooks.aws_ofi_nccl.variant = "cuda12"
   ```
