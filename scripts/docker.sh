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
    "
}

declare -a containers

build_unique(){
    NAME=$1
    SCRIPT_DIR=$2
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
                "$SCRIPT_DIR/scripts/templates/template-api-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$SCRIPT_DIR/scripts/templates/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml";;
        "frontend")
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                "$SCRIPT_DIR/scripts/templates/template-frontend-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile"
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$SCRIPT_DIR/scripts/templates/template-compose.conf" > "$CURRENT_DIR/$NAME/docker-compose.yaml";;
        "db")
            cp "$SCRIPT_DIR/scripts/templates/template-db-compose.conf" "$CURRENT_DIR/$NAME/docker-compose.yaml"
            
            if [ -z "${scaffold_data["docker-run"]}" ]; then
                echo "docker-run=docker compose up" >> $CURRENT_DIR/$NAME/scaffold.kubefs
            fi
            echo "$NAME component built successfuly, run using 'kubefs docker exec'"
            return 0;;
        *) default_helper 1 "${scaffold_data["type"]}";;
    esac

    # build docker image
    (cd $CURRENT_DIR/$NAME && docker buildx build -t $NAME .)

    echo "$NAME component built successfuly, run using 'kubefs docker exec'"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "docker-run=docker compose up" >> $CURRENT_DIR/$NAME/scaffold.kubefs
    fi

    return 0
}

build_all(){
    SCRIPT_DIR=$1
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            build_unique $name $SCRIPT_DIR

        fi
    done
}

build(){
    SCRIPT_DIR=$1
    name=$2

    if [ -z $name ]; then
        default_helper 0
        return 1
    fi
    case $name in
        "all") build_all $SCRIPT_DIR;;
        "--help") default_helper 0;;
        *) build_unique $name $SCRIPT_DIR;;
    esac
}

execute_unique(){
    NAME=$1
    SCRIPT_DIR=$2
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
        connection_string="mongodb://user:pass@localhost:27018/?directConnection=true"
        echo "Connection String: $connection_string"
    fi

    cd $CURRENT_DIR/$NAME && ${scaffold_data["docker-run"]} > /dev/null 2>&1

    return 0
}

execute_all(){
    SCRIPT_DIR=$1
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            execute_unique $name $SCRIPT_DIR &
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
    SCRIPT_DIR=$1
    name=$2

    if [ -z $name ]; then
        default_helper 0
        return 1
    fi

    case $name in
        "all") execute_all $SCRIPT_DIR;;
        "--help") default_helper 0;;
        *) execute_unique $name $SCRIPT_DIR;;
    esac
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    if [ -z $1 ]; then
        default_helper 0
        return 1
    fi

    # source helper functions 
    source $SCRIPT_DIR/scripts/helper.sh
    validate_project

    type=$1
    shift
    case $type in
        "build") build $SCRIPT_DIR $@;;
        "exec") execute $SCRIPT_DIR $@;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac
}

main $@
exit 0


