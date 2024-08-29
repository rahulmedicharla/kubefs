#!/bin/bash
default_helper() {
    echo "
    kubefs remove - delete a resource locally and from docker hub

    Usage: kubefs remove <COMMAND> [ARGS]
        kubefs remove all - delete all resources locally and from docker hub
        kubefs remove <name> - delete specified resource locally and from docker hub
        kubefs remove --help - display this help message

        Args:
            --no-local: Don't delete from local
            --no-remote: Don't delete from docker hub
    "
}

parse_optional_params(){
    declare -A opts

    opts["--no-local"]=false
    opts["--no-remote"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --no-local)
                opts["--no-local"]=true
                ;;
            --no-remote)
                opts["--no-remote"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

remove_all(){
    echo "Removing all resources..."
    
    CURRENT_DIR=`pwd`
    names=()

    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}
            names+=($name)
            
            remove_unique $name $@

            if [ $? -eq 1 ]; then
                print_error "Error occured deleting $NAME. Please try again or use 'kubefs --help' for more information."
                return 0
            fi
        fi
    done

    for name in "${names[@]}"; do
        remove_from_manifest $name
    done

    print_success "All components removed successfully."
    return 0
}

remove_helper(){
    NAME=$1
    shift

    remove_unique $NAME $@

    if [ $? -eq 1 ]; then
        print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
        return 0
    fi

    remove_from_manifest $NAME

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

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    eval "$(parse_optional_params $@)"
    eval "$(parse_scaffold $NAME)"

    if [ "${opts["--no-remote"]}" == false ]; then

        echo "Deleting docker repo for $NAME..."

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

        print_success "$NAME Docker repository deleted successfully!"

    fi

    if [ "${opts["--no-local"]}" == false ]; then

        docker rm $NAME-container-1 > /dev/null 2>&1
        docker rmi $NAME > /dev/null 2>&1
        docker rmi "${scaffold_data["docker-repo"]}" > /dev/null 2>&1

        rm -rf $CURRENT_DIR/$NAME
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
