#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs docker - create and test docker images for created resources to be deployed onto the clusters

    kubefs docker build all - build for all components
    kubefs docker build <name> - build for singular component
    kubefs docker exec all - run all components from created docker images
    kubefs docker exec <name> - run singular component from created docker image
    kubefs docker push all - push all components to docker hub
    kubefs docker push <name> - push singular component to docker hub
    "
}

declare -a containers

build_unique(){
    NAME=$1
    CURRENT_DIR=`pwd`
    echo "Building $NAME component..."

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        default_helper 1 $NAME
        return 1
    fi

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
            echo "Don't need to build docker image for database components."
            return 0;;
        *) default_helper 1 "${scaffold_data["type"]}";;
    esac

    # build docker image
    cd $CURRENT_DIR/$NAME && docker buildx build -t $NAME .

    if [ $? -eq 1 ]; then
        echo "$NAME component was not built successfuly. Please try again."
        return 1
    fi

    echo "$NAME component built successfuly, run using 'kubefs docker exec' or push using 'kubefs docker push'"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "docker-run=docker compose up" >> $CURRENT_DIR/$NAME/scaffold.kubefs
    fi

    return 0
}

build_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            build_unique $name

        fi
    done
}

build(){
    name=$1
    if [ -z $name ]; then
        default_helper 0
        return 1
    fi

    case $name in
        "all") build_all;;
        "--help") default_helper 0;;
        *) build_unique $name;;
    esac
}

execute_unique(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        default_helper 1 $NAME
        return 1
    fi

    eval "$(parse_scaffold "$NAME")"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "Docker image not built for $NAME, please build using 'kubefs docker build'. "
        return 1
    fi

    echo "Running $NAME component on port ${scaffold_data["port"]} using docker image $NAME..."
    if [ "${scaffold_data["type"]}" == "db" ]; then
        echo "Connect to $NAME using 'docker exec -it $NAME-$NAME-1 cqlsh'"
    fi

    cd $CURRENT_DIR/$NAME && ${scaffold_data["docker-run"]}

    return 0
}

execute_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            execute_unique $name &
            containers+=($name) 
        fi
    done

    echo "Use Ctrl C. to stop all components..."

    exit_flag=0
    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done
}

cleanup(){
    CURRENT_DIR=`pwd`
    echo "Stopping all components..."
    for container in "${containers[@]}"; do
        (cd $CURRENT_DIR/$container && docker-compose down)
    done
    exit_flag=1
    exit 0
}

trap cleanup SIGINT

execute(){
    name=$1

    if [ -z $name ]; then
        default_helper 0
        return 1
    fi

    case $name in
        "all") execute_all;;
        "--help") default_helper 0;;
        *) execute_unique $name;;
    esac
}

push_unique(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        default_helper 1 $NAME
        return 1
    fi

    eval "$(parse_scaffold "$NAME")"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "Docker image not built for $NAME, please build using 'kubefs docker build'. "
        return 1
    fi

    if [ "${scaffold_data["type"]}" == "db" ]; then
        echo "You don't need to push a database component to docker hub. Use 'kubefs docker exec' to run the component"
        return 0
    fi

    echo "Pushing $NAME component to docker hub..."

    docker tag $NAME "${scaffold_data["docker-repo"]}"
    sudo docker push "${scaffold_data["docker-repo"]}"

    if [ $? -eq 1 ]; then
        echo "$NAME component was not pushed to docker hub. Please try again."
        return 1
    fi

    echo "$NAME component pushed to docker hub successfully"

    return 0
}

push_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            push_unique $name

        fi
    done
}

push(){
    name=$1

    if [ -z $name ]; then
        default_helper 0
        return 1
    fi

    case $name in
        "all") push_all;;
        "--help") default_helper 0;;
        *) push_unique $name;;
    esac
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
        "build") build $@;;
        "exec") execute $@;;
        "push") push $@;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac
}

main $@
exit 0


