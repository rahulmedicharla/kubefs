#!/bin/bash
default_helper() {
    echo "
    kubefs remove - delete a resource locally and from docker hub

    Usage: kubefs remove <COMMAND> [ARGS]
        kubefs remove all - delete all resources locally and from docker hub
        kubefs remove <name> - delete specified resource locally and from docker hub
        kubefs remove --help - display this help message

        Args:
            --no-local | -nl: Don't delete from local
            --no-remote | -nr: Don't delete from docker hub
    "
}

parse_optional_params(){
    declare -A opts

    opts["--no-local"]=false
    opts["--no-remote"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --no-local | -nl)
                opts["--no-local"]=true
                ;;
            --no-remote | -nr)
                opts["--no-remote"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

remove_repo(){
    NAME=$1

    output=$(pass show kubefs/config/docker > /dev/null 2>&1)

    if [ $? -eq 1 ]; then
        print_warning "Docker configurations not found. Please run 'kubefs config docker' to login to docker ecosystem"
        return 1
    fi

    docker_auth=$(pass show kubefs/config/docker | jq -r '.')
    username=$(echo $docker_auth | jq -r '.username')
    password=$(echo $docker_auth | jq -r '.password')

    response=$(curl -s -X POST "https://hub.docker.com/v2/users/login/" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$username\", \"password\": \"$password\"}")

    if [ $? -ne 0 ]; then
        print_error "Failed to login to Docker. Please try again."
        return 1
    fi

    token=$(echo $response | jq -r '.token')
    
    delete_repo_response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "https://hub.docker.com/v2/repositories/$username/$NAME/" \
        -H "Authorization: JWT $token" \
    )

    if [ "$delete_repo_response" -ne 202 ]; then
        print_error "Failed to delete Docker repository for $NAME. Please try again."
        return 1
    fi

    return 0
}

remove_all(){
    echo "Removing all resources..."
    
    CURRENT_DIR=`pwd`

    manifest_data=$(yq e '.resources[].name' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"

    for name in "${manifest_data[@]}"; do

        remove_unique $name $@

        if [ $? -eq 1 ]; then
            print_error "Error occured deleting $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    done

    print_success "All resources removed successfully."
    return 0
}

remove_helper(){
    NAME=$1
    shift

    remove_unique $NAME $@

    if [ $? -eq 1 ]; then
        print_error "Error occured removing $NAME. Please try again or use 'kubefs --help' for more information."
        return 1
    fi

    return 0
}

remove_unique(){
    NAME=$1
    shift
    CURRENT_DIR=`pwd`

    echo "Removing $NAME..."

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    eval "$(parse_optional_params $@)"
    docker_repo=$(yq e '.project.docker-repo' "$CURRENT_DIR/$NAME/scaffold.yaml")
    type=$(yq e '.project.type' $CURRENT_DIR/$NAME/scaffold.yaml)

    if [ "${opts["--no-remote"]}" == false ]; then

        echo "Deleting docker repo for $NAME..."

        IFS=$'\n' read -r -d '' -a remove_remote < <(yq e '.remove.remote[]' "$CURRENT_DIR/$NAME/scaffold.yaml" && printf '\0')
        for cmd in "${remove_remote[@]}"; do
            eval "$cmd"

            if [ $? -eq 1 ]; then
                print_error "Error occurred executing command: $cmd. Please try again."
                return 1
            fi
        done

        if [ $? -eq 1 ]; then
            print_error "Error occured deleting $NAME Docker repository. Please try again."
            return 1
        fi

        print_success "$NAME Docker repository deleted successfully!"

    fi

    if [ "${opts["--no-local"]}" == false ]; then

        echo "Deleting $NAME locally..."

        IFS=$'\n' read -r -d '' -a remove_docker < <(yq e '.remove.docker[]' "$CURRENT_DIR/$NAME/scaffold.yaml" && printf '\0')
        for cmd in "${remove_docker[@]}"; do
            eval "$cmd"

        done

        IFS=$'\n' read -r -d '' -a remove_local < <(yq e '.remove.local[]' "$CURRENT_DIR/$NAME/scaffold.yaml" && printf '\0')
        for cmd in "${remove_local[@]}"; do
            eval "$cmd"
        done

    fi
    
    print_success "$NAME removed successfully"
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
        "all") remove_all $@;;
        "--help") default_helper;;
        *) remove_helper $COMMAND $@;;
    esac
}

main $@
exit 0
