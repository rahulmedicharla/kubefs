#!/bin/bash
default_helper() {
    echo "
    kubefs compile - build and push docker images for all components

    Usage: kubefs compile <COMMAND> [ARGS]
        kubefs compile all - build and push docker images for all components
        kubefs compile <name> - build and push docker image for singular component
        kubefs compile --help - display this help message

        Args:
            --no-build: Don't build docker images
            --no-push: Don't push docker images to docker hub
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

    manifest_data=$(yq e '.resources[].name' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"

    for name in "${manifest_data[@]}"; do
        compile_unique $name $@

        if [ $? -eq 1 ]; then
            print_error "Error occured compiling $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
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

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
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

    type=$(yq e '.project.type' $CURRENT_DIR/$NAME/scaffold.yaml)
    port=$(yq e '.project.port' $CURRENT_DIR/$NAME/scaffold.yaml)
    entry=$(yq e '.project.entry' $CURRENT_DIR/$NAME/scaffold.yaml)
    docker_run=$(yq e '.up.docker' $CURRENT_DIR/$NAME/scaffold.yaml)
    
    env_vars=$(yq e '.resources[].env' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a env_vars <<< "$env_vars"

    case "$type" in
        "api")
            sed -e "s/{{PORT}}/${port}/" \
                -e "s/{{NAME}}/$NAME/" \
                "$KUBEFS_CONFIG/scripts/templates/local-api/template-api-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{PORT}}/${port}/" \
                -e "s/{{HOST_PORT}}/${port}/" \
                -e "s/{{NAME}}/$NAME/" \
                "$KUBEFS_CONFIG/scripts/templates/shared/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml"

            for env in "${env_vars[@]}"; do
                yq e ".services.container.environment += [\"$env\"]" $CURRENT_DIR/$NAME/docker-compose.yaml -i
            done
            ;;  
        "frontend")
            sed -e "s/{{PORT}}/${port}/" \
                -e "s/{{ENTRY}}/${entry}/" \
                "$KUBEFS_CONFIG/scripts/templates/local-frontend/template-frontend-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{HOST_PORT}}/${port}/" \
                -e "s/{{PORT}}/${port}/" \
                -e "s/{{NAME}}/$NAME/" \
                "$KUBEFS_CONFIG/scripts/templates/shared/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml"
            
            for env in "${env_vars[@]}"; do
                yq e ".services.container.environment += [\"$env\"]" $CURRENT_DIR/$NAME/docker-compose.yaml -i
            done    
            ;;
        "db")
            host=$(hostname -I | awk '{print $1}')

            sed -e "s/{{HOSTIP}}/${host}/" \
                -e "s/{{HOST_PORT}}/${port}/" \
                -e "s/{{PORT}}/${port}/" \
                -e "s/{{ENTRY}}/${entry}/" \
                "$KUBEFS_CONFIG/scripts/templates/local-db/template-db-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml"
            
            if [ "$docker_run" == "null" ]; then
                yq e '.up.docker = "docker compose up"' $CURRENT_DIR/$NAME/scaffold.yaml -i
                yq e '.down.docker = "docker compose down"' $CURRENT_DIR/$NAME/scaffold.yaml -i
                yq e '.remove.docker += ["docker rm $NAME-container-1 > /dev/null 2>&1", "docker volume rm ${NAME}_cassandra_data > /dev/null 2>&1", "docker rm network ${NAME}_cassandra_network > /dev/null 2>&1"]' $CURRENT_DIR/$NAME/scaffold.yaml -i
            fi

            for env in "${env_vars[@]}"; do
                yq e ".services.container.environment += [\"$env\"]" $CURRENT_DIR/$NAME/docker-compose.yaml -i
            done

            print_success "$NAME prepared successfully"
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

    if [ "$docker_run" == "null" ]; then
        yq e '.up.docker = "docker compose up"' $CURRENT_DIR/$NAME/scaffold.yaml -i
        yq e '.down.docker = "docker compose down"' $CURRENT_DIR/$NAME/scaffold.yaml -i
        yq e '.remove.docker += ["docker rm $NAME-container-1 > /dev/null 2>&1", "docker rmi $NAME > /dev/null 2>&1", "docker rmi ${docker_repo} > /dev/null 2>&1"]' $CURRENT_DIR/$NAME/scaffold.yaml -i
    fi

    print_success "$NAME built successfully"

    return 0
}

push(){
    NAME=$1
    CURRENT_DIR=`pwd`

    type=$(yq e '.project.type' $CURRENT_DIR/$NAME/scaffold.yaml)
    docker_run=$(yq e '.up.docker' $CURRENT_DIR/$NAME/scaffold.yaml)
    docker_repo=$(yq e '.project.docker-repo' $CURRENT_DIR/$NAME/scaffold.yaml)

    if [ "$docker_run" == "null" ]; then
        print_warning "Docker image not built for $NAME, please build using 'kubefs compile'. "
        return 1
    fi

    if [ "$type" == "db" ]; then
        print_warning "You don't need to push a database component to docker hub. Use 'kubefs run' to run the component"
        return 0
    fi

    echo "Pushing $NAME component to docker hub..."

    docker tag $NAME "$docker_repo"
    docker push "$docker_repo"

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
