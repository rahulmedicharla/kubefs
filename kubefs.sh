#!/bin/bash

function default_helper {
    echo "${1} is not a valid argument, please follow types below
    kubefs - a cli tool to create & deploy full stack applications onto kubernetes clusters

    kubefs build - create docker images & helm charts for created resources to be deployed onto the clusters
    kubefs config - config login credentials & deployment targets to be used 
    kubefs create - easily create backend, frontend, & db constructs to be used within your application
    kubefs deploy - deploy the build targets onto the cluster!
    kubefs init <project_name> - download all required dependencies & set up configuration files
    kubefs test - run go components to test your code
    "
}

function init_project {
    if [ -z $1 ]; then
        default_helper $2
        return 1;
    fi

    #Downloading brew if not downloaded
    echo "Downloading brew..."
    if !(command -v brew &> /dev/null); then
        echo "Installing homebrew package manager..."
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)";
        test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
    fi

    #Downloading go if not downloaded
    echo "Downloading go"
    if !(command -v go &> /dev/null); then
        echo "Installing go..."
        mkdir $HOME/go
        echo "" >> ~/.bashrc && echo '''export GOPATH=$HOME/go''' >> ~/.bashrc
        echo '''export GOROOT="$(brew --prefix golang)/libexec"''' >> ~/.bashrc
        echo '''export PATH="$PATH:${GOPATH}/bin:${GOROOT}/bin"''' >> ~/.bashrc
        source ~/.bashrc
        brew install go
    fi


    # prompt to download minikube
    echo "Downloading minikube"
    if !(command -v minikube &> /dev/null); then
        echo "Please follow these instructions to install minikube
        https://minikube.sigs.k8s.io/docs/start/"
    fi

    # prompt to download docker
    echo "Downloading docker"
    if !(command -v docker &> /dev/null); then
        echo "Please follow these instructions to install docker
        https://docs.docker.com/engine/install/ubuntu/"
    fi 

    # create project directory && configuration files
    touch manifest.sh
    echo "export KUBEFS_NAME=\"$1\"" >> manifest.sh && echo "export KUBEFS_ROOT=\"`pwd`\"" >> manifest.sh
    source "`pwd`/manifest.sh"
}

if [ -f "${KUBEFS_ROOT}/manifest.sh" ]; then
    source "${KUBEFS_ROOT}/manifest.sh"
fi

case $1 in 
    "build") source ./scripts/build.sh;;
    "config") source ./scripts/config.sh;;
    "create") source ./scripts/create.sh;;
    "deploy") source ./scripts/deploy.sh;;
    "init") init_project $2;;
    "exec") source ./scripts/exec.sh;;
    "--help") default_helper $1;;
    *) default_helper $1;;
esac

exit 0


