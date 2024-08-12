#!/bin/bash

default_helper() {
    echo "${2} is not a valid argument, please follow types below
    kubefs create - easily create backend, frontend, & db constructs to be used within your application

    kubefs create api <name> - creates a sample GET api called name using golang 
    "
}

create_helper_func() {
    FUNC=$1
    CURRENT_DIR=$2
    NAME=$3

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi

    if [ -d "`pwd`/$NAME" ]; then
        echo "A component with that name already exists, please try a different name"
        return 1
    fi

    # call specified function
    $FUNC $NAME $CURRENT_DIR
    if [ $? -eq 1 ]; then
        rm -rf `pwd`/$NAME
        return 0
    fi
    
    echo "$NAME api was created successfully!"
    return 0
}

create_api() {
    NAME=$1
    CURRENT_DIR=$2
    PORT=8080
    ENTRY=main.go
    SCAFFOLD="scaffold.kubefs"

    mkdir `pwd`/$NAME
    (cd `pwd`/$NAME && go mod init $NAME)
    sed -e "s/{{PORT}}/$PORT/" \
        "$CURRENT_DIR/scripts/templates/template-api.conf" > "`pwd`/$NAME/$ENTRY"
    
    (cd `pwd`/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD)
    
    return 0
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
        "api") create_helper_func create_api $SCRIPT_DIR $3;;
        "--help") default_helper;;
        *) default_helper ;;
    esac    
}
main $@
exit 0


