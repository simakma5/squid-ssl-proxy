#!/bin/bash

## Functions

# Display usage instructions for the script
__usage() {
  if [[ "$1" != "" ]]; then
      echo "ERR: $1 "
  fi
  echo "Usage: $0
          -i|--image-name <DockerImageName>
          -p|--platforms <PlatformsList>
          -w|--work-dir <WorkDirPath>
          -t|--git-tag <TagName(Required)>
          -a|--extra-args <ExtraArgsForDockerBuildCommand>
          --mark-latest
          --push-images
          --push-git-tags
          --no-cache
          --load
          -h|--help"
  echo "Description:"
  echo "  -i|--image-name : Name of the docker image."
  echo "    e.g. squid-ssl-proxy. (Def: current directory name)"
  echo "  -p|--platforms  : list of platforms to build for."
  echo "    (Def: linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6)"
  echo "  -w|--work-dir   : Docker buildx command work dir path"
  echo "  -t|--git-tag    : Name for git tag to create (Required)"
  echo "  -a|--extra-args : Extra docker buidl args to pass to docker build command"
  echo "  --mark-latest   : Marks the latest image to given tag"
  echo "  --push-images   : Enables pushing of docker images to docker hub"
  echo "  --push-git-tags : Enabled push of git tags to git remote origin"
  echo "  --no-cache      : Avoid use of docker build cache"
  echo "  --load          : Make locally built images available to build"
  echo "  -h|--help       : Prints this help menu"
  exit 1
}

# Process and validate input parameters
__processParams() {
  extraDockerArgs=""
  imageTags=""
  while [ "$1" != "" ]; do
    case $1 in
      -i|--image-name) shift
                       [[ ! $1 ]] && __usage "Image name is missing"
                       image="$1"
                       ;;
      -p|--platforms)  shift
                       [[ ! $1 ]] && __usage "Platforms list missing"
                       platforms="$1"
                       ;;
      -w|--work-dir)   shift
                       [[ ! $1 ]] && __usage "Work dir path missing"
                       workDir="$1"
                       ;;
      -t|--git-tag)    shift
                       [[ ! $1 ]] && __usage "Git tag name missing"
                       tagName="$(echo "$1"\
                       |sed -e 's/^[ \t]*//;s/[ \t]*$//;s/ /-/g'\
                       |sed $'s/[^[:print:]\t]//g')"
                       imageTags+=" $tagName"
                       ;;
      -a|--extra-args)    shift
                       [[ ! $1 ]] && __usage "extra args missing"
                       extraDockerArgs+=" $1"
                       ;;
      --mark-latest)   imageTags+=" latest"
                       ;;
      --push-images)   imgPush=yes
                       ;;
      --push-git-tags) tagPush=yes
                       ;;
      --no-cache)      extraDockerArgs+=" --no-cache"
                       ;;
      --load)      extraDockerArgs+=" --load"
                       ;;
      -h|--help)       __usage
                       ;;
      * )              __usage "Missing or incorrect parameters"
    esac
    shift
  done
  [[ ! $platforms ]] && \
  platforms="linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6"
  [[ ! $imgPush ]] && imgPush=no
  [[ ! $tagPush ]] && tagPush=no
  [[ ! $tagName ]] && __usage "Work dir path missing"
  [[ ! $workDir ]] && workDir="$(pwd)"
  [[ ! $image ]] && image=$(basename "$(pwd)")
}

# Check for errors and exit if any are found
__errCheck(){
  # $1 = errocode
  # $2 = msg
  [[ "$1" != "0" ]] && echo "ERR: $2" && exit "$1"
}

# Build Docker images using buildx
__dockerBuild(){
  # $1 = image name e.g. "squid-ssl-proxy"
  # $2 = image tags e.g. "latest 1.1.1"
  # $3 = platforms e.g. "linux/amd64,linux/arm64"
  # $4 = work dir path
  # $5 = Extra args for docker buildx command

  tagParams=""
  for i in $2; do tagParams+=" -t $1:$i"; done
  # shellcheck disable=SC2086
  sudo docker buildx build --platform "$3" $5 $tagParams "$4"
  __errCheck "$?" "Docker Build failed"
}

# Perform validations for the build environment
__validations() {
  ! [[ "$imgPush" =~ ^(yes|no)$ ]] && imgPush=no
  ! [[ "$tagPush" =~ ^(yes|no)$ ]] && tagPush=no

  # Check for buildx env
  if [[ "$(sudo docker buildx ls\
           |grep -ce '.*default.*running.*linux/amd64' \
          )" -lt "1" ]]; then
    __errCheck "1" "Docker buildx env is not setup, please fix it"
  fi
}

# Ensure the source code is up-to-date if pushing images
__checkSource() {
  if [[ "$imgPush" == "yes" ]]; then
    git checkout main >/dev/null 2>&1
    __errCheck "$?" "Git checkout to main branch failed..."
    git pull >/dev/null 2>&1
    __errCheck "$?" "Git pull for main branch failed..."
  fi
}

# Set up Docker buildx environment
__setupDocker() {
  # Lets prepare docker image
  if [[ "$imgPush" == "yes" ]]; then
    echo "INFO: Logging in to Docker HUB... (Interactive Mode)"
    sudo docker login 2>&1 | sed 's/^/INFO: DOCKER: /g'
    __errCheck "$?" "Docker login failed..."
    extraDockerArgs+=" --push"
  fi
  sudo docker buildx create --name builder >/dev/null 2>&1
  sudo docker buildx use builder >/dev/null 2>&1
  __errCheck "$?" "Could not use docker buildx default runner..."
}

# Create and optionally push a Git tag
__createGitTag() {
  # Lets create git tag
  echo "INFO: Creating local git tag: $tagName"
  git tag -d "$tagName" >/dev/null 2>&1
  git tag "$tagName" >/dev/null 2>&1
  if [[ "$tagPush" == "yes" ]]; then
    echo "INFO: Pushing git tag to remote: $tagName"
    git push --delete origin "$tagName" >/dev/null 2>&1
    git push -f origin "$tagName" >/dev/null 2>&1
  fi
}

## Main script execution
__processParams "$@"
__validations
__checkSource
__setupDocker

# Build Docker images
echo "INFO: Building Docker Images (may take a while)"
echo "INFO: Docker image      : $image"
echo "INFO: Platforms         : $platforms"
echo "INFO: Docker image tags : $imageTags"
echo "INFO: Image tags push?  : $imgPush"
echo "INFO: Git tags          : $tagName"
echo "INFO: Git tags push?    : $tagPush"
__dockerBuild "$image" "$imageTags" "$platforms" "$workDir" "$extraDockerArgs"

# Create and push Git tags
__createGitTag "$tagName"
