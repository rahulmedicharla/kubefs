#!/bin/bash
default_helper() {
    TYPE=$1
    if [ $TYPE -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs auth - authenticate into your kubefs account
    kubefs auth login <email> <password> - login to your kubefs account
    "
}

create_doc(){
    local_id=$1

}

download_dependencies(){
    if pass show kubefs/auth &> /dev/null; then
        echo "Already setup kubefs configurations. Use 'kubefs auth login' to login"
        return 0
    fi

    echo -e "\e[1mSetting up kubefs configurations for the first time...\e[0m"
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

    if [ ! -f $SCRIPT_DIR/scripts/.env ]; then
        echo "Invalid Firebase API Key, please enter a valid key"
        return 1  
    fi

    # grab apikey
    apikey=$(cat $SCRIPT_DIR/scripts/.env | grep FIREBASE_API_KEY | cut -d '=' -f2)

    # enter email & password for account registration
    echo "Enter your email to create your kubefs account: "
    read EMAIL
    echo "Enter your password to create your kubefs account: "
    read PASSWORD

    # Check if GPG key exists
    if ! gpg --list-keys | grep -q "pub"; then
        echo "No GPG key found. Generating a new GPG key..."
        gpg --full-generate-key
    fi

    # List keys and get the key ID
    key_id=$(gpg --list-keys | grep -A 1 "pub" | tail -n 1 | awk '{print $1}')

    # Initialize pass with the GPG key
    pass init "$key_id"
    
    response=$(curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apikey" \
        -H "Content-Type: application/json" \
        --data-binary '{"email":"'"$EMAIL"'","password":"'"$PASSWORD"'","returnSecureToken":true}'
    )

    # Parse the response
    id_token=$(echo $response | jq -r '.idToken')
    refresh_token=$(echo $response | jq -r '.refreshToken')
    error_message=$(echo $response | jq -r '.error.message')
    expires_in=($(echo $response | jq -r '.expiresIn'))
    issued_at=$(date +%s)
    local_id=$(echo $response | jq -r '.localId')

    # Check if account creation was successful
    if [ "$id_token" != "null" ]; then
        echo ""
        echo "Account creation successful!"

        auth_data=$(jq -n \
        --arg id_token "$id_token" \
        --arg refresh_token "$refresh_token" \
        --arg expires_in "$expires_in" \
        --arg issued_at "$issued_at" \
        '{id_token: $id_token, refresh_token: $refresh_token, expires_in: $expires_in, issued_at: $issued_at}')

        echo "$auth_data" | pass insert -m kubefs/auth

        create_doc $local_id
        
    else
        echo "Account creation failed: $error_message"
        echo "Please try again."
        return 1
    fi
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"  
    init_project $SCRIPT_DIR
}

main $@
exit 0


