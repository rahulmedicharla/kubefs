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

exec_unique(){
    NAME=$1

    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ ! -d "$CURRENT_DIR/$NAME" ]; then
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

    case $2 in
        "all") exec_all;;
        "--help") default_helper 0;;
        *) exec_unique $2;;
    esac    
}
main $@
exit 0@
exit 0


