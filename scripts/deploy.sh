#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs deploy - manage kubernetes deployments on clusters

    kubefs deploy all - deploy all built components onto specified clusters
    kubefs deploy <name> - deploy specified component onto cluster

    optional paramaters:
        -t <local|EKS|Azure|GCP> - specify the deployment target for which cluster (default is local)
    "
}

parse_optional_params(){
    declare -A opts
    while getopts "t:" opt; do
        case ${opt} in
            t)
                if [ $OPTARG == "local" ] || [ $OPTARG == "EKS" ] || [ $OPTARG == "Azure" ] || [ $OPTARG == "GCP" ]; then
                    opts["target"]=$OPTARG
                else
                    echo "Invalid target: $OPTARG" 1>&2
                fi;;
            \? )
                echo "Invalid option: $OPTARG" 1>&2
                ;;
        esac
    done

    echo $(declare -p opts)
}

deploy_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    eval $(parse_optional_params $@)

    TARGET="local"

    if [ -n "${opts["target"]}" ]; then
        TARGET=${opts["target"]}
    fi

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            deploy_unique $CURRENT_DIR $name $TARGET
        fi
    done

    echo "Deployed all components"
    return 0
}

deploy_helper(){
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

    eval $(parse_optional_params $@)

    TARGET="local"

    if [ -n "${opts["target"]}" ]; then
        TARGET=${opts["target"]}
    fi
    deploy_unique $CURRENT_DIR $NAME $TARGET
}

deploy_unique(){
    CURRENT_DIR=$1
    NAME=$2
    TARGET=$3

    eval "$(parse_scaffold "$NAME")"

    echo "Deploying $NAME component"
    helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy
    return 0
}

main(){
    if [ -z $1 ]; then
        default_helper 0
        return 1
    fi

    # source helper functions 
    source $KUBEFS_CONFIG/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        return 0
    fi

    type=$1
    case $type in
        "all") deploy_all;;
        "--help") default_helper 0;;
        *) deploy_helper $@;;
    esac    
}
main $@
exit 0