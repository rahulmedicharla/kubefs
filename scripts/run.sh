#!/bin/bash
default_helper() {
    echo "
    kubefs run - run a resource locally or in the docker containers

    Usage: kubefs run <COMMAND> [ARGS]
        kubefs run all - run all resources locally or in the docker containers
        kubefs run <name> - run specific resource locally or in the docker containers
        kubefs run --help - display this help message

        Args:
            --platform <local|docker> : Specify the platform to run the resource 
    "
}

parse_optional_params(){
    declare -A opts

    opts["--platform"]=local

    while [ $# -gt 0 ]; do
        case $1 in
            --platform)
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

declare -a pids

run_all(){
    echo "Running all components..."
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"
    eval "$(parse_optional_params $@)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}
            type=${manifest_data[$i+5]#*=}
            
            run_unique $name "${opts[@]}" &
            pids+=($!:$name:$type:"${opts["--platform"]}")
        fi
    done

    echo "Use Ctrl C. to stop serving all components..."

    exit_flag=0
    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done
}

run_unique(){
    NAME=$1
    opts=$2
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    eval "$(parse_scaffold "$NAME")"

    if [ "${opts["--platform"]}" == "docker" ]; then
        if [ -z "${scaffold_data["docker-run"]}" ]; then
            print_warning "Docker image not built for $NAME, please build using 'kubefs docker build'. "
            return 1
        fi
        
        echo "Running $NAME component on port ${scaffold_data["port"]} using docker image $NAME..."
        
        if [ "${scaffold_data["type"]}" == "db" ]; then
            echo "Connect to $NAME using 'docker exec -it $NAME-container-1 cqlsh'"
        fi

        (cd $CURRENT_DIR/$NAME && ${scaffold_data["docker-run"]})

    else
        if [ -z "${scaffold_data["command"]}" ]; then
            print_error "No command specified for $NAME."
            return 1
        fi

        echo "Serving $NAME on port ${scaffold_data["port"]}"
        echo "Use Ctrl C. to stop serving $NAME"

        (cd $CURRENT_DIR/$NAME && ${scaffold_data["command"]} > /dev/null 2>&1)
    fi

    return 0
}

run_helper(){
    NAME=$1
    shift
    eval "$(parse_optional_params $@)"

    run_unique $NAME "${opts[@]}"

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

            if [ $platform == "docker" ]; then
                (cd $CURRENT_DIR/$name && docker-compose down)
            else
                if [ $type == "db" ]; then
                    docker-compose down 2>/dev/null
                else
                    kill $pid 2>/dev/null
                fi
            fi
        done
        exit_flag=1
        pids=()  
    fi
}

trap cleanup SIGINT

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
        "all") run_all $@;;
        "--help") default_helper;;
        *) run_helper $COMMAND $@;;
    esac    
}
main $@
exit 0