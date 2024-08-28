#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs undeploy - undeploy the created resources from the clusters

    kubefs undeploy all - undeploy all components from the clusters
    kubefs undeploy <name> - undeploy singular component from the clusters
    "
}

undeploy_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}
            entry=${manifest_data[$i+2]#*=}
            port=${manifest_data[$i+3]#*=}
            command=${manifest_data[$i+4]#*=}
            type=${manifest_data[$i+5]#*=}
            
            helm uninstall $name
        fi
    done

    echo "Successfully undeployed all components"

    return 0
}

undeploy_unique(){
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

    helm uninstall $NAME

    echo "Successfully undeployed $NAME component"

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
        "all")  undeploy_all;;
        "--help") default_helper 0;;
        *) undeploy_unique $type;;
    esac
}

main $@
exit 0


