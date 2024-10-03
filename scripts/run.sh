#!/bin/bash
default_helper() {
    echo "
    kubefs run - run a resource locally or in the docker containers

    Usage: kubefs run <COMMAND> [ARGS]
        kubefs run all - run all resources locally or in the docker containers
        kubefs run <name> - run specific resource locally or in the docker containers
        kubefs run --help - display this help message

        Args:
            --platform | -p <local|docker> : Specify the platform to run the resource 
    "
}

parse_optional_params(){
    declare -A opts

    opts["--platform"]=local

    while [ $# -gt 0 ]; do
        case $1 in
            --platform | -p)
                if [ "$2" == "local" ] || [ "$2" == "docker" ]; then
                    opts["--platform"]=$2
                    shift
                fi 
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

orig_stty_settings=$(stty -g)

declare -a pids

run_all(){
    echo "Running all components..."
    CURRENT_DIR=`pwd`

    eval "$(parse_optional_params $@)"

    manifest_data=$(yq e '.resources[] | .name + ":" + .type' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"

    if [ ${opts["--platform"]} == "local" ]; then

        env_vars=$(yq e '.resources[].local[]' $CURRENT_DIR/manifest.yaml)
        IFS=$'\n' read -r -d '' -a env_vars <<< "$env_vars"

        for project_info in "${manifest_data[@]}"; do
            name=$(echo $project_info | cut -d ":" -f 1)
            type=$(echo $project_info | cut -d ":" -f 2)

            if [ -z $name ]; then
                default_helper
                return 1
            fi

            if [ ! -f "$CURRENT_DIR/$name/scaffold.yaml" ]; then
                print_error "$name is not a valid resource"
                default_helper
                return 1
            fi

            if [ -f $CURRENT_DIR/$name/".secrets" ]; then
                env_vars+=($(cat $CURRENT_DIR/$name/".secrets"))
            fi
        done

        (cd $CURRENT_DIR/kubefs-api && rm .env 2>/dev/null && touch .env)
        for env_var in "${env_vars[@]}"; do
            (cd $CURRENT_DIR/kubefs-api && echo $env_var >> .env)
        done

        (cd $CURRENT_DIR/kubefs-api && go run .) &
        pids+=($!:$name:kubefs:local)
    fi

    if [ "${opts["--platform"]}" == "docker" ]; then
        if ! docker network ls | grep -q "shared_network"; then
            print_warning "Creating shared_network"
            docker network create shared_network
        fi
    fi

    exit_flag=0

    for project_info in "${manifest_data[@]}"; do
        name=$(echo $project_info | cut -d ":" -f 1)
        type=$(echo $project_info | cut -d ":" -f 2)

        if [ -z $name ]; then
            default_helper
            return 1
        fi

        if [ ! -f "$CURRENT_DIR/$name/scaffold.yaml" ]; then
            print_error "$name is not a valid resource"
            default_helper
            return 1
        fi

        docker_run=$(yq e '.up.docker' $CURRENT_DIR/$name/scaffold.yaml)
        local_run=$(yq e '.up.local' $CURRENT_DIR/$name/scaffold.yaml)

        if [ "${opts["--platform"]}" == "docker" ] && [ "$docker_run" == "null" ]; then
            print_warning "Docker image not built for $NAME, please build using 'kubefs compile'. "
            continue
        fi

        if [ "${opts["--platform"]}" == "local" ] && [ "$local_run" == "null" ]; then
            print_warning "No local_run specified for $name. not running"
            continue
        fi

        run_unique $name "${opts[@]}" &
        pids+=($!:$name:$type:"${opts["--platform"]}")

    done

    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done
}

run_unique(){
    NAME=$1
    opts=$2
    CURRENT_DIR=`pwd`

    port=$(yq e '.project.port' $CURRENT_DIR/$NAME/scaffold.yaml)
    type=$(yq e '.project.type' $CURRENT_DIR/$NAME/scaffold.yaml)
    local_run=$(yq e '.up.local' $CURRENT_DIR/$NAME/scaffold.yaml)
    docker_run=$(yq e '.up.docker' $CURRENT_DIR/$NAME/scaffold.yaml)
    framework=$(yq e '.project.framework' $CURRENT_DIR/$NAME/scaffold.yaml)

    if [ "${opts["--platform"]}" == "docker" ]; then
        
        echo "Running $NAME component on port $port using docker image $NAME..."
        
        if [ "$type" == "db" ]; then
            echo "Connect to $NAME using 'cqlsh' or 'mongosh' client"
        fi

        (cd $CURRENT_DIR/$NAME && $docker_run)

    else

        echo "Serving $NAME on port $port"
        echo "Use Ctrl C. to stop serving $NAME"

        (cd $CURRENT_DIR/$NAME && eval $local_run)
    fi

    return 0
}

run_helper(){
    name=$1
    CURRENT_DIR=`pwd`
    shift
    eval "$(parse_optional_params $@)"

    if [ -z $name ]; then
        default_helper
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$name/scaffold.yaml" ]; then
        print_error "$name is not a valid resource"
        default_helper
        return 1
    fi

    exit_flag=0

    docker_run=$(yq e '.up.docker' $CURRENT_DIR/$name/scaffold.yaml)
    local_run=$(yq e '.up.local' $CURRENT_DIR/$name/scaffold.yaml)
    
    if [ "${opts["--platform"]}" == "docker" ] && [ "$docker_run" == "null" ]; then
        print_warning "Docker image not built for $NAME, please build using 'kubefs compile'. "
        return 1
    fi

    if [ "${opts["--platform"]}" == "local" ] && [ "$local_run" == "null" ]; then
        print_error "No local_run specified for $name."
        return 0
    fi

    if [ "${opts["--platform"]}" == "local" ]; then
        env_vars=$(yq e '.resources[].local[]' $CURRENT_DIR/manifest.yaml)
        IFS=$'\n' read -r -d '' -a env_vars <<< "$env_vars"

        if [ -f $CURRENT_DIR/$name/".secrets" ]; then
            env_vars+=($(cat $CURRENT_DIR/$name/".secrets"))
        fi

        (cd $CURRENT_DIR/kubefs-api && rm .env 2>/dev/null && touch .env)
        for env_var in "${env_vars[@]}"; do
            (cd $CURRENT_DIR/kubefs-api && echo $env_var >> .env)
        done

        (cd $CURRENT_DIR/kubefs-api && go run .) &
        pids+=($!:$name:kubefs:local)
    fi

    if [ "${opts["--platform"]}" == "docker" ]; then
        if ! docker network ls | grep -q "shared_network"; then
            print_warning "Creating shared_network"
            docker network create shared_network
        fi
    fi

    run_unique $name "${opts[@]}" & 
    pids+=($!:$name:$type:"${opts["--platform"]}")

    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done

    return 0
}

cleanup(){
    CURRENT_DIR=`pwd`
    if [ ${#pids[@]} -gt 0 ]; then
        echo "Stopping all resources..."

        for pid_info in "${pids[@]}"; do
            pid=$(echo $pid_info | cut -d ":" -f 1)
            name=$(echo $pid_info | cut -d ":" -f 2)
            type=$(echo $pid_info | cut -d ":" -f 3)
            platform=$(echo $pid_info | cut -d ":" -f 4)

            if [ "$type" == "kubefs" ]; then
                kill $pid 2>/dev/null
                continue
            fi

            docker_down=$(yq e '.down.docker' $CURRENT_DIR/$name/scaffold.yaml)

            if [ "$platform" == "docker" ]; then
                (cd $CURRENT_DIR/$name && $docker_down)
            else
                if [ "$type" == "db" ]; then
                    $docker_down 2>/dev/null
                else
                    kill $pid 2>/dev/null
                fi
            fi
        done
        exit_flag=1
        pids=()  
    fi
    stty $orig_stty_settings
    return 0
}

trap cleanup SIGINT

main(){
    local_run=$1
    shift
    if [ -z $local_run ]; then
        default_helper
        return 0
    fi

    source $KUBEFS_CONFIG/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        return 1
    fi

    case $local_run in
        "all") run_all $@;;
        "--help") default_helper;;
        *) run_helper $local_run $@;;
    esac    
}
main $@
exit 0