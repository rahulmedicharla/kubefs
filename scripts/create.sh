#!/bin/bash

default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs create - easily create backend, frontend, & db constructs to be used within your application

    kubefs create api <name> - creates a sample GET api called <name> using golang 

    optional paramaters:
        -p <port> - specify the port number for the api (default is 8080)
        -e <entry_file> - specify the entry file for the api (default is main.go)
    "
}

parse_optional_params(){
    declare -A opts
    while getopts "p:e:" opt; do
        case ${opt} in
            p)
                opts["port"]=$OPTARG
                ;;
            e)
                opts["entry"]=$OPTARG
                ;;
            \? )
                echo "Invalid option: $OPTARG" 1>&2
                ;;
        esac
    done

    echo $(declare -p opts)
}

create_helper_func() {
    FUNC=$1
    NAME=$2
    shift 2

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ -d "`pwd`/$NAME" ]; then
        echo "A component with that name already exists, please try a different name"
        return 1
    fi

    eval $(parse_optional_params $@)

    # call specified function
    $FUNC $NAME
    if [ $? -eq 1 ]; then
        rm -rf `pwd`/$NAME
        return 0
    fi
    
    echo "$NAME api was created successfully!"
    return 0
}

validate_port(){
    CASE=$1
    if grep -q "$CASE" "`pwd`/manifest.kubefs"; then
        return 1
    fi
    
    return 0
}

create_api() {
    NAME=$1

    PORT=8080
    ENTRY=main.go

    if [ -n "${opts["port"]}" ]; then
        PORT=${opts["port"]}
    fi
    if [ -n "${opts["entry"]}" ]; then
        ENTRY=${opts["entry"]}
    fi    

    validate_port port=$PORT
    if [ $? -eq 1 ]; then
        echo "Port $PORT is already in use, please use a different port"
        return 1
    fi
    
    SCAFFOLD=scaffold.kubefs

    mkdir `pwd`/$NAME
    (cd `pwd`/$NAME && go mod init $NAME)
    sed -e "s/{{PORT}}/$PORT/" \
        -e "s/{{PROJECT_NAME}}/$NAME/" \
        "$SCRIPT_DIR/scripts/templates/template-api.conf" > "`pwd`/$NAME/$ENTRY"
    
    (cd `pwd`/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD && echo "command=go run $ENTRY" >> $SCAFFOLD)
    append_to_manifest $NAME $ENTRY $PORT "go run $ENTRY"

    return 0
}


append_to_manifest() {
    CURRENT_DIR=`pwd`
    NAME=$1
    ENTRY=$2
    PORT=$3
    COMMAND=$4

    echo "" >> $CURRENT_DIR/manifest.kubefs && echo "--" >> $CURRENT_DIR/manifest.kubefs
    echo "name=$NAME" >> $CURRENT_DIR/manifest.kubefs
    echo "entry=$ENTRY" >> $CURRENT_DIR/manifest.kubefs
    echo "port=$PORT" >> $CURRENT_DIR/manifest.kubefs
    echo "command=$COMMAND" >> $CURRENT_DIR/manifest.kubefs
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
    shift
    case $type in
        "api") create_helper_func create_api $@;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac    
}
main $@
exit 0


