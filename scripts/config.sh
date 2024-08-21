#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs config - customize your project & auth congifurations

    kubefs config list - list all configurations
    kubefs config docker - configure docker configurations
    "
}

list_configurations(){
    echo "MongoDB configurations"
    pass show kubefs/config/mongo
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
    echo "Please enter password or PAT:"
    read -s password

    output=$(echo "$password" | sudo docker login --username "$username" --password-stdin 2>&1)
    if [ $? -eq 1 ]; then
        echo "" && echo "Docker login failed. Please try again or create account at https://hub.docker.com"
        return 1
    fi

    echo $output

    validate_gpg_key

    docker_auth=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        '{username: $username, password: $password}'    
    )

    echo "$docker_auth" | pass insert -m kubefs/config/docker
}

main(){
    if [ -z $1 ]; then
        default_helper 0
        return 1
    fi

    # source helper functions 
    source $KUBEFS_CONFIG/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        return 0
    fi

    type=$1
    shift
    case $type in
        "list") list_configurations;;
        "docker") docker_config $@;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac
}

main $@
exit 0