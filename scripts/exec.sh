#!/bin/bash

default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs exec - easily execute some or all applications that were built

    kubefs exec all - executes all components within the project 

    kubefs exec <name> - executes a specific component within the project
    "
}

declare -a pids

exec_all(){
    # read manifest.kubefs
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}
            entry=${manifest_data[$i+2]#*=}
            port=${manifest_data[$i+3]#*=}
            command=${manifest_data[$i+4]#*=}

            cd $CURRENT_DIR/$name; $command &
            pids+=($!)
            echo "Starting $name on port $port with PID $!"
        fi
    done

    wait
}

cleanup(){
    echo ""
    echo "Stopping all background processes..."
    for pid in "${pids[@]}"; do
        echo "Stopping PID $pid"
        kill $pid 2>/dev/null
    done
    pids=()
    exit 0 
}

trap cleanup SIGINT

exec_unique(){
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

    if [ -n "${scaffold_data["command"]}" ]; then
        (cd $CURRENT_DIR/$NAME && ${scaffold_data["command"]})
    fi
    
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    # source helper functions 
    source $SCRIPT_DIR/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        rm -rf `pwd`/$NAME
        return 0
    fi

    type=$1
    case $type in
        "all") exec_all;;
        "--help") default_helper 0;;
        *) exec_unique $type;;
    esac    
}

main $@
exit 0


