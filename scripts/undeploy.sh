#!/bin/bash
default_helper() {
    echo "
    kubefs undeploy - undeploy the created resources from the clusters

    Usage: kubefs undeploy <COMMAND> [ARGS]
        kubefs undeploy all - undeploy all components from the clusters
        kubefs undeploy <name> - undeploy singular component from the clusters
        kubefs undeploy --help - display this help message

        Args:
            --target | -t <local|EKS|azure|GCP> - specify the deployment target for which cluster (default is local)
            --close | -c - stop cluster after undeploying components
    "
}

parse_optional_params(){
    declare -A opts

    opts["--target"]=local
    opts["--close"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --target | -t)
                if [ "$2" == "local" ] || [ "$2" == "EKS" ] || [ "$2" == "azure" ] || [ "$2" == "GCP" ]; then
                    opts["--target"]=$2
                    shift
                fi 
                ;;
            --close | -c)
                opts["--close"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

undeploy_all(){
    echo "Undeploying all components..."

    CURRENT_DIR=`pwd`
    eval "$(parse_optional_params $@)"

    manifest_data=$(yq e '.resources[].name' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"

    for name in "${manifest_data[@]}"; do

        undeploy_unique $name "${opts[@]}"

        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 0
        fi
    done

    print_success "Undeployed all components"
    return 0
}

undeploy_helper(){
    NAME=$1
    shift
    eval "$(parse_optional_params $@)"

    undeploy_unique $NAME "${opts[@]}"

    if [ $? -eq 1 ]; then
        print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
        return 0
    fi

    return 0
}

undeploy_azure(){
    NAME=$1
    echo "Undeploying $NAME from Azure..."

    if ! az account show > /dev/null 2>&1; then
        print_warning "Azure account not logged in. Please login using 'kubefs config azure'"
        return 1
    fi

    helm uninstall $NAME     
    if [ $? -eq 1 ]; then
        print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
        return 1
    fi
    print_success "$NAME undeployed successfully"

    if [ "${opts["--close"]}" == true ]; then
        while kubectl get namespaces | grep -q terminating; do
            sleep 2
        done
        
        az aks stop --name $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml) --resource-group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml)
        if [ $? -eq 1 ]; then
            print_error "Error occured stopping the cluster. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
        print_success "Cluster stopped successfully"

    fi

    return 0
}

undeploy_unique(){
    NAME=$1
    opts=$2
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi  

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Undeploying $NAME ..."
    
    case ${opts["--target"]} in
        # "EKS") deploy_eks $NAME;;
        "azure") undeploy_azure $NAME;;
        # "GCP") deploy_gcp $NAME;;
        *)
            helm uninstall $NAME 

            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi

            if [ "${opts["--close"]}" == true ]; then
                while kubectl get namespaces | grep -q terminating; do
                    sleep 2
                done
                minikube stop
            fi
            ;;
    esac

    print_success "$NAME undeployed successfully"
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
        "all") undeploy_all $@;;
        "--help") default_helper;;
        *) undeploy_helper $COMMAND $@;;
    esac
}

main $@
exit 0


