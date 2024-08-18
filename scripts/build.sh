#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs build - create docker images & helm charts for created resources to be deployed onto the clusters

    kubefs build all - build for all components
    kubefs build <name> - build for singular component
    "
}

build_unique(){
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

    case "${scaffold_data["type"]}" in
        "api")
            sed -e "s/{{PORT}}/${scaffold_data["port"]}/" \
                -e "s/{{NAME}}/${scaffold_data["name"]}/" \
                "$SCRIPT_DIR/scripts/templates/template-api-dockerfile.conf" > "$CURRENT_DIR/$NAME/Dockerfile";;
        *) default_helper 1 "${scaffold_data["type"]}";;
    esac

    # build docker image
    cd $CURRENT_DIR/$NAME && docker buildx build -t $NAME .

    echo "$NAME component build successfuly, run using 'kubefs exec'"
    return 0
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
    case $type in
        "all")  build_all;;
        "--help") default_helper 0;;
        *) build_unique $type $SCRIPT_DIR;;
    esac
}

main $@
exit 0


