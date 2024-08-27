#!/bin/bash
default_helper() {
    TYPE=$1
    if [ $TYPE -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs setup - download dependencies & setup configurations for first time.
    "
}

download_dependencies(){
    echo "Setting up kubefs configurations for the first time..."
    echo "Verifying dependencies..."

    if !(command -v brew &> /dev/null); then
        echo "Installing homebrew package manager..."
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)";
        test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
    fi

    #Downloading go if not downloaded
    if !(command -v go &> /dev/null); then
        echo "Installing go..."
        mkdir $HOME/go
        echo "" >> ~/.bashrc && echo '''export GOPATH=$HOME/go''' >> ~/.bashrc
        echo '''export GOROOT="$(brew --prefix golang)/libexec"''' >> ~/.bashrc
        echo '''export PATH="$PATH:${GOPATH}/bin:${GOROOT}/bin"''' >> ~/.bashrc
        source ~/.bashrc
        brew install go
    fi

    # prompt to download colima
    if !(command -v colima &> /dev/null); then
        echo "Downloading colima..."
        brew install colima
        colima start --kubernetes
        helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace > /dev/null 2>&1
        colima stop
    fi

    # prompt to download docker
    if !(command -v docker &> /dev/null); then
        echo "Downloading docker..."
        brew install docker
    fi 

    if !(command -v docker compose &> /dev/null); then
        echo "Downloading docker compose..."
        brew install docker-compose
    fi

    if !(command -v node &> /dev/null); then
        echo "Downloading node..."
        brew install node
    fi

    if !(command -v atlas &> /dev/null); then
        echo "Downloading mongodb atlas..."
        brew install mongodb-atlas
    fi

    if !(command -v jq &> /dev/null); then
        echo "Downloading jq..."
        brew install jq
    fi

    if !(command -v curl &> /dev/null); then
        echo "Downloading curl..."
        brew install curl
    fi

    if !(command -v pass &> /dev/null); then
        echo "Downloading pass..."
        brew install pass
    fi

    if !(command -v helm &> /dev/null); then
        echo "Downloading helm..."
        brew install helm
    fi
}

init_project() {

    if [ ! -z $KUBEFS_CONFIG ]; then
        echo "Kubefs has already been setup. use 'kubefs --help' for more information"
        return 0
    fi

    if grep -q "export KUBEFS_CONFIG" ~/.bashrc; then
        echo "Kubefs has already been setup. run 'source ~/.bashrc' to start using kubefs"
        return 0
    fi

    download_dependencies

    echo "export KUBEFS_CONFIG="$SCRIPT_DIR"" >> ~/.bashrc

    echo "" && echo "Account creation successful!"
    echo "Please run 'source ~/.bashrc' to start using kubefs"
    return 0
        
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"  
    init_project $SCRIPT_DIR
}

main $@
exit 0


