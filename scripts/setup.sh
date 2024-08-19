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

    # prompt to download minikube
    if !(command -v minikube &> /dev/null); then
        echo "Downloading minikube..."
        brew install minikube
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
}
init_project() {
    SCRIPT_DIR=$1

    download_dependencies

    # # Check if GPG key exists
    # if ! gpg --list-keys | grep -q "pub"; then
    #     echo "No GPG key found. Generating a new GPG key..."
    #     gpg --full-generate-key
    # fi

    # # List keys and get the key ID
    # key_id=$(gpg --list-keys | grep -A 1 "pub" | tail -n 1 | awk '{print $1}')

    # # Initialize pass with the GPG key
    # pass init "$key_id"

    # auth_data=$(jq -n \
    # --arg setup "$id_token" \
    # --arg expires_in "$expires_in" \
    # --arg issued_at "$issued_at" \
    # --arg uid "$uid" \
    # --arg refresh_token "$refresh_token" \
    # '{id_token: $id_token, expires_in: $expires_in, issued_at: $issued_at, uid: $uid, refresh_token: $refresh_token}')

    # echo "$auth_data" | pass insert -m kubefs/auth

    # if [ $? -eq 1 ]; then
    #     echo "Account creation failed. Please try again."
    #     return 1
    # fi

    echo ""
    echo "Account creation successful!"
    return 0
        
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"  
    init_project $SCRIPT_DIR
}

main $@
exit 0


