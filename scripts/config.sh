#!/bin/bash
default_helper() {
    echo "
    kubefs config - configure kubefs environment and auth configurations

    Usage: kubefs config <COMMAND>
        kubefs config list - list all configuration data
        kubefs config docker - configure docker configurations
        kubefs config --help - display this help message
    "
}

list_configurations(){
    echo "Docker configurations:"
    pass show kubefs/config/docker
}

validate_gpg_key(){
    if ! gpg --list-keys | grep -q "pub"; then
        echo "No GPG key found. Generating a new GPG key..."
        gpg --full-generate-key
    fi

    # List keys and get the key ID
    key_id=$(gpg --list-keys | grep -A 1 "pub" | tail -n 1 | awk '{print $1}')

    # Initialize pass with the GPG key
    pass init "$key_id"
}

docker_config(){
    echo "Configuring docker configurations..."
    echo "Please enter Docker ID or email:"
    read username

    if [ -z $username ]; then
        print_error "Username can't be empty"
        return 1
    fi

    echo "Please enter password or PAT:"
    read -s password

    if [ -z $password ]; then
        print_error "Password can't be empty"
        return 1
    fi

    output=$(echo "$password" | sudo docker login --username "$username" --password-stdin 2>&1)
    if [ $? -eq 1 ]; then
        echo "" && echo "Docker login failed. Please try again or create account at https://hub.docker.com"
        return 1
    fi

    validate_gpg_key

    docker_auth=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        '{username: $username, password: $password}'    
    )

    echo "$docker_auth" | pass insert -m kubefs/config/docker

    return 0
}

main(){
    COMMAND=$1
    shift
    if [ -z $COMMAND ]; then
        default_helper
        return 0
    fi

    source $KUBEFS_CONFIG/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        return 1
    fi

    case $COMMAND in
        "list") list_configurations;;
        "docker") docker_config $@;;
        "--help") default_helper;;
        *) default_helper;;
    esac
}

main $@
exit 0