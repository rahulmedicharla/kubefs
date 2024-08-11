#!/bin/bash

default_helper() {
    echo "${2} is not a valid argument, please follow types below
    kubefs create - easily create backend, frontend, & db constructs to be used within your application

    kubefs create api <name> - creates a sample GET api called name using golang 

    "
}

function_cleaner() {
    FUNC=$1
    CURRENT_DIR=$2
    NAME=$3

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi

    if [ -d "${KUBEFS_ROOT}/$NAME" ]; then
        echo "A component with that name already exists, please try a different name"
        return 1
    fi

    # call specified function
    $FUNC $NAME $CURRENT_DIR
    if [ $? -eq 1 ]; then
        rm -rf ${KUBEFS_ROOT}/$NAME
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

    mkdir ${KUBEFS_ROOT}/$NAME
    (cd ${KUBEFS_ROOT}/$NAME && go mod init $NAME)
    (cd ${KUBEFS_ROOT}/$NAME &&
        sed -e "s/{{PORT}}/$PORT/" \
        "$CURRENT_DIR/scripts/templates/template-api.conf" > "${KUBEFS_ROOT}/$NAME/$ENTRY" )
    
    (cd ${KUBEFS_ROOT}/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD)

    return 0
}


if [ ! -f "${KUBEFS_ROOT}/manifest.sh" ]; then
    echo "You are not in a valid project folder, please initialize project using kubefs init or look at kubefs --help for more information"
    return 1
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
case $2 in
    "api") function_cleaner create_api $SCRIPT_DIR $3;;
    "--help") default_helper;;
    *) default_helper ;;
esac

exit 0


