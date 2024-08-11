#!/bin/bash

function default_helper {
    echo "${2} is not a valid argument, please follow types below
    kubefs create - easily create backend, frontend, & db constructs to be used within your application

    kubefs create api <name> - creates a sample GET api called name using golang 

    "
}

function create_api {
    if [ -z $1 ]; then
        default_helper
        return 1;
    fi

    if [ -d "${KUBEFS_ROOT}/$1" ]; then
        echo "That component already exists, please try a different name"
        return 1
    fi
    
    TEMPLATE_DIR="/scripts/templates/template-api.conf"
    mkdir ${KUBEFS_ROOT}/$1
    (cd ${KUBEFS_ROOT}/$1 && go mod init $1)
    (cd ${KUBEFS_ROOT}/$1 &&
        sed -e "s/{{PACKAGE_NAME}}/$1/" \
        "${TEMPLATE_DIR}" > "${KUBEFS_ROOT}/$1/main.go" )
    
    return 0
}

if [! -f "${KUBEFS_ROOT}/manifest.sh" ]; then
    echo "You are not in a valid project folder, please initialize project using kubefs init or look at kubefs --help for more information"
    return 1
fi

case $2 in
    "api") create_api $3;;
    "--help") default_helper;;
    *) default_helper ;;
esac

exit 0


