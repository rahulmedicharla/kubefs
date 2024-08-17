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
            type=${manifest_data[$i+5]#*=}
            
            cd $CURRENT_DIR/$name; $command > /dev/null 2>&1 &
            pids+=($!:$name:$type)
            echo "Serving $name on port $port"
        fi
    done

    echo "Use Ctrl C. to stop serving all components..."

    exit_flag=0
    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done
}

cleanup(){
    echo ""
    for pid_info in "${pids[@]}"; do
        pid=$(echo $pid_info | cut -d ":" -f 1)
        name=$(echo $pid_info | cut -d ":" -f 2)
        type=$(echo $pid_info | cut -d ":" -f 3)

        echo "Stopping $name"
        if [ $type == "db" ]; then
            atlas deployment pause $name 2>/dev/null
        else
            kill $pid 2>/dev/null
        fi
    done
    exit_flag=1
    pids=()
}

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
        (cd $CURRENT_DIR/$NAME && ${scaffold_data["command"]} > /dev/null 2>&1) &
        pids+=($!:$NAME:${scaffold_data["type"]})
    fi

    echo "Serving $NAME on port ${scaffold_data["port"]}"
    echo "Use Ctrl C. to stop serving $NAME"
    
    exit_flag=0
    while [ "$exit_flag" -eq "0" ]; do
        sleep 1
    done
}

trap cleanup SIGINT

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


