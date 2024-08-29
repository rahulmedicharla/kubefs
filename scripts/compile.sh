#!/bin/bash
default_helper() {
    echo "
    kubefs compile - build and push docker images for all components

    Usage: kubefs compile <COMMAND> [ARGS]
        kubefs compile all - build and push docker images for all components
        kubefs compile <name> - build and push docker image for singular component
        kubefs compile --help - display this help message

        Args:
            --no-build: Only push docker image
            --no-push: Only build docker image
    "
}

parse_optional_params(){
    declare -A opts

    opts["--no-build"]=false
    opts["--no-push"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --no-build)
                opts["--no-build"]=true
                ;;
            --no-push)
                opts["--no-push"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

compile_all(){
    echo "Compiling all resources..."
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            compile_unique $name $@

            if [ $? -eq 1 ]; then
                print_error "Error occured building $NAME. Please try again or use 'kubefs --help' for more information."
                return 0
            fi
        fi
    done

    print_success "All components compiled successfully."
    return 0
}

compile_unique(){
    NAME=$1
    shift
    CURRENT_DIR=`pwd`

    echo "Compiling $NAME..."

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
    

    if [ "${opts["--no-build"]}" == false ]; then
        build $NAME

        if [ $? -eq 1 ]; then
            return 1
        fi

    fi
    
    if [ "${opts["--no-push"]}" == false ]; then
        push $NAME

        if [ $? -eq 1 ]; then
            return 1
        fi
    fi

    print_success "$NAME compiled successfully"
    return 0

}

build(){
    NAME=$1
    CURRENT_DIR=`pwd`
    echo "Building $NAME..."

    eval "$(parse_scaffold "$NAME")"

    case "${scaffold_data["type"]}" in
        "api")
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$KUBEFS_CONFIG/scripts/templates/template-api-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{HOST_PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$KUBEFS_CONFIG/scripts/templates/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml";;
        "frontend")
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                "$KUBEFS_CONFIG/scripts/templates/template-frontend-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{HOST_PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$KUBEFS_CONFIG/scripts/templates/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml";;
        "db")
            print_warning "Don't need to build docker image for database components."
            return 0;;
        *) default_helper;;
    esac

    # remove old docker image
    docker rmi $NAME > /dev/null 2>&1

    # build docker image
    (cd $CURRENT_DIR/$NAME && docker buildx build -t $NAME .)

    if [ $? -eq 1 ]; then
        print_error "$NAME component was not built successfuly. Please try again."
        return 1
    fi

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "docker-run=docker compose up" >> $CURRENT_DIR/$NAME/scaffold.kubefs
    fi

    print_success "$NAME built successfully"

    return 0
}

push(){
    NAME=$1
    CURRENT_DIR=`pwd`
    echo "Pushing $NAME..."

    eval "$(parse_scaffold "$NAME")"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        print_warning "Docker image not built for $NAME, please build using 'kubefs docker build'. "
        return 1
    fi

    if [ "${scaffold_data["type"]}" == "db" ]; then
        print_warning "You don't need to push a database component to docker hub. Use 'kubefs docker exec' to run the component"
        return 0
    fi

    echo "Pushing $NAME component to docker hub..."

    docker tag $NAME "${scaffold_data["docker-repo"]}"
    sudo docker push "${scaffold_data["docker-repo"]}"

    if [ $? -eq 1 ]; then
        print_error "$NAME component was not pushed to docker hub. Please try again."
        return 1
    fi

    print_success "$NAME pushed successfully"

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
        "all") compile_all $@;;
        "--help") default_helper;;
        *) compile_unique $COMMAND $@;;
    esac
}

main $@
exit 0
