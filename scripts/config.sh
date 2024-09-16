#!/bin/bash
default_helper() {
    echo "
    kubefs config - configure kubefs environment and auth configurations

    Usage: kubefs config <COMMAND>
        kubefs config azure - manage azure configurations
        kubefs config docker - manage docker configurations
        kubefs config google - manage google configurations
        kubefs config list - list all configuration data
        kubefs config --help - display this help message

        Args:
            --remove | -r - remove the configuration & all resources from remote
    "
}

parse_optional_params(){
    declare -A opts

    opts["--remove"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --remove | -r)
                opts["--remove"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

list_configurations(){
    echo "Docker configurations:"
    pass show kubefs/config/docker
    echo "Azure accounts":
    az account list
    echo "Google accounts:"
    gcloud auth list --format="value(account)"
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

azure_config(){
    echo "Configuring Azure configurations..."
    CURRENT_DIR=$(pwd)
    
    eval $(parse_optional_params $@)
    if [ ${opts["--remove"]} = true ]; then
        print_warning "Logging out of Azure account, delete resources & groups at https://portal.azure.com manually"
        az logout
        if [ $? -eq 1 ]; then
            print_error "Azure logout failed. Please try again or create account at https://portal.azure.com"
            return 1
        fi
        yq eval 'del(.azure)' -i $CURRENT_DIR/manifest.yaml
        return 0
    fi

    az login
    if [ $? -eq 1 ]; then
        print_error "Azure login failed. Please try again or create account at https://portal.azure.com"
        return 1
    fi

    echo "Set resource group name: "
    read resource_group
    echo "Set cluster name: "
    read cluster_name
    echo "Set location: "
    read location

    if ! az account list-locations --query "[].name" -o tsv | grep -q "^$location$"; then
        print_error "Invalid location: $location. Please enter a valid Azure region."
        az logout
        return 1
    fi

    yq e -i ".azure.location = \"$location\"" $CURRENT_DIR/manifest.yaml
    yq e -i ".azure.resource_group = \"$resource_group\"" $CURRENT_DIR/manifest.yaml
    yq e -i ".azure.cluster_name = \"$cluster_name\"" $CURRENT_DIR/manifest.yaml

    return 0
}

google_config(){
    echo "Configuring Google configurations..."
    CURRENT_DIR=$(pwd)
    
    eval $(parse_optional_params $@)
    if [ ${opts["--remove"]} = true ]; then   
        print_warning "Logging out of Google account, delete resources & groups at https://console.cloud.google.com manually"
        gcloud auth revoke
        if [ $? -eq 1 ]; then
            print_error "Google logout failed. Please try again or create account at https://console.cloud.google.com"
            return 1
        fi
        yq eval 'del(.google)' -i $CURRENT_DIR/manifest.yaml
        return 0
    fi

    gcloud auth login
    if [ $? -eq 1 ]; then
        print_error "Google login failed. Please try again or create account at https://console.cloud.google.com"
        return 1
    fi

    echo "Enter project ID to use/create: "
    read project_id
    echo "Enter region to use: "
    read region
    echo "Enter cluster name: "
    read cluster_name

    
    if ! gcloud projects list --format="value(projectId)" | grep -q "^$project_id$"; then
        echo "Creating project $project_id..."
        gcloud projects create $project_id
        if [ $? -ne 0 ]; then
            print_error "Failed to create project. Please try again."
            return 1
        fi
    fi
    
    gcloud config set project $project_id 2>/dev/null

    if ! gcloud services list --enabled --format="value(config.name)" | grep -q "compute.googleapis.com"; then
        echo "Compute Engine API is not enabled. Enabling it now..."
        gcloud services enable compute.googleapis.com
        if [ $? -ne 0 ]; then
            print_error "Failed to enable Compute Engine API. Please try again."
            return 1
        fi
    fi

    if ! gcloud compute regions list --format="value(name)" | grep -q "^$region$"; then
        print_error "Invalid region: $region. Please enter a valid Google Cloud region."
        return 1
    fi

    yq e -i ".google.project_id = \"$(gcloud config get-value project)\"" $CURRENT_DIR/manifest.yaml
    yq e -i ".google.region = \"$region\"" $CURRENT_DIR/manifest.yaml
    yq e -i ".google.cluster_name = \"$cluster_name\"" $CURRENT_DIR/manifest.yaml

    return 0
}

docker_config(){
    echo "Configuring docker configurations..."
    
    eval $(parse_optional_params $@)
    if [ ${opts["--remove"]} = true ]; then
        pass rm kubefs/config/docker
        return 0
    fi

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
        print_error "Docker login failed. Please try again or create account at https://hub.docker.com"
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
        "azure") azure_config $@;;
        "docker") docker_config $@;;
        "google") google_config $@;;
        "list") list_configurations;;
        "--help") default_helper;;
        *) default_helper;;
    esac
}

main $@
exit 0