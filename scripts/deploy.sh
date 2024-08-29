#!/bin/bash
default_helper() {
    echo "
    kubefs deploy - create helm charts & deploy the build targets onto the cluster

    Usage: kubefs deploy <COMMAND> [ARGS]
        kubefs deploy all - deploy all built components onto specified clusters
        kubefs deploy <name> - deploy specified component onto cluster
        kubefs deploy --help - display this help message

        Args:
            --target <local|EKS|Azure|GCP> - specify the deployment target for which cluster (default is local)
    "
}

helmify(){
    NAME=$1
    eval "$(parse_scaffold $NAME)"

    if [ -z "${scaffold_data["docker-run"]}" ]; then
        print_warning "Docker Image is not built for $NAME component. Please build and push the image"
        return 1
    fi

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
    
    case "${scaffold_data["type"]}" in
        "api") helmify_api $NAME;;
        "frontend") helmify_frontend $NAME;;
        "db") helmify_database $NAME;;
    esac

    echo "Helm Chart created for $NAME..."
}

parse_optional_params(){
    declare -A opts

    opts["--target"]=local

    while [ $# -gt 0 ]; do
        case $1 in
            --target)
                if [ "$2" == "local" ] || [ "$2" == "EKS" ] || [ "$2" == "Azure" ] || [ "$2" == "GCP" ]; then
                    opts["--target"]=$2
                    shift
                fi 
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

deploy_all(){
    echo "Deploying all components..."
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"
    eval "$(parse_optional_params $@)"

    if ! colima status > /dev/null 2>&1; then
        print_warning "Colima is not running. Starting Colima with 'colima start -k'"
        colima start
    fi

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            deploy_unique $name "${opts[@]}"

            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 0
            fi
        fi
    done

    print_success "Deployed all components"
    return 0
}

deploy_helper(){
    NAME=$1
    shift
    eval "$(parse_optional_params $@)"

    if ! colima status > /dev/null 2>&1; then
        print_warning "Colima is not running. Starting Colima with 'colima start -k'"
        colima start
    fi

    deploy_unique $NAME "${opts[@]}"

    if [ $? -eq 1 ]; then
        print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
        return 0
    fi

    return 0
}

deploy_unique(){
    NAME=$1
    opts=$2
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi  

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Deploying $NAME ..."

    eval "$(parse_optional_params $@)"
    
    case ${opts["--target"]} in
        # "EKS") deploy_eks $NAME;;
        # "Azure") deploy_azure $NAME;;
        # "GCP") deploy_gcp $NAME;;
        *)
            rm -rf $CURRENT_DIR/$NAME/deploy
            helmify $NAME

            if [ $? -eq 1 ]; then
                return 1
            fi

            helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy 

            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
            ;;
    esac

    print_success "$NAME deployed successfully"
    return 0
}

main(){
    COMMAND=$1
    shift
    if [ -z $COMMAND ]; then
        default_helper
        return 0
    fi

    source $KUBEFS_CONFIG/scripts/helper.sh
    validate_project

    if [ $? -eq 1 ]; then
        return 1
    fi

    case $COMMAND in
        "all") deploy_all $@;;
        "--help") default_helper;;
        *) deploy_helper $COMMAND $@;;
    esac    
}
main $@
exit 0