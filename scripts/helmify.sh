#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs helmify - create helm charts for created resources to be deployed onto the clusters

    kubefs helmify all - create helm charts for all components
    kubefs helmify <name> <endpoint> - create helm chart for singular component,
    "
}

helmify_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            helmify_unique $name

        fi
    done

    echo "Helm charts created for all components"
    return 0
}

helmify_unique(){
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

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        echo "Docker Image is not built for $NAME component. Please build and push the image"
        return 1
    fi

    echo "Helmifying $NAME component..."
    rm -rf $CURRENT_DIR/$NAME/deploy

    case "${scaffold_data["type"]}" in
        "api") helmify_api $NAME;;
        "frontend") helmify_frontend $NAME;;
        "db") helmify_database $NAME;;
    esac
    
    echo "Helm chart created for $NAME component"
    
    return 0
}

helmify_database(){
    NAME=$1
    cp -r $KUBEFS_CONFIG/scripts/templates/deploy-db $CURRENT_DIR/$NAME/deploy
    sed -e "s#{{NAME}}#$NAME#" \
        -e "s#{{IMAGE}}#cassandra#" \
        -e "s#{{PORT}}#${scaffold_data["port"]}#" \
        -e "s#{{TAG}}#latest#" \
        -e "s#{{SERVICE_TYPE}}#None#" \
        "$KUBEFS_CONFIG/scripts/templates/helm-values.conf" > "$CURRENT_DIR/$NAME/deploy/values.yaml"
}

helmify_frontend(){
    NAME=$1
    cp -r $KUBEFS_CONFIG/scripts/templates/deploy-fe $CURRENT_DIR/$NAME/deploy
    sed -e "s#{{NAME}}#$NAME#" \
        -e "s#{{IMAGE}}#${scaffold_data["docker-repo"]}#" \
        -e "s#{{PORT}}#${scaffold_data["port"]}#" \
        -e "s#{{TAG}}#latest#" \
        -e "s#{{SERVICE_TYPE}}#LoadBalancer#" \
        "$KUBEFS_CONFIG/scripts/templates/helm-values.conf" > "$CURRENT_DIR/$NAME/deploy/values.yaml"
}

helmify_api(){
    NAME=$1
    cp -r $KUBEFS_CONFIG/scripts/templates/deploy-api $CURRENT_DIR/$NAME/deploy
    sed -e "s#{{NAME}}#$NAME#" \
        -e "s#{{IMAGE}}#${scaffold_data["docker-repo"]}#" \
        -e "s#{{PORT}}#${scaffold_data["port"]}#" \
        -e "s#{{TAG}}#latest#" \
        -e "s#{{SERVICE_TYPE}}#ClusterIP#" \
        "$KUBEFS_CONFIG/scripts/templates/helm-values.conf" > "$CURRENT_DIR/$NAME/deploy/values.yaml"
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
        "all")  helmify_all;;
        "--help") default_helper 0;;
        *) helmify_unique $type;;
    esac
}

main $@
exit 0


