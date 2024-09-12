#!/bin/bash
default_helper() {
    echo "
    kubefs deploy - create helm charts & deploy the build targets onto the cluster

    Usage: kubefs deploy <COMMAND> [ARGS]
        kubefs deploy all - deploy all built components onto specified clusters
        kubefs deploy <name> - deploy specified component onto cluster
        kubefs deploy --help - display this help message

        Args:
            --target | -t <local|EKS|Azure|GCP> - specify the deployment target for which cluster (default is local)
            --no-deploy | -nd: Don't deploy the helm chart, only create the helm chart
            --no-helmify | -nh: Don't create the helm chart
    "
}

parse_optional_params(){
    declare -A opts

    opts["--target"]=local
    opts["--no-deploy"]=false
    opts["--no-helmify"]=false

    while [ $# -gt 0 ]; do
        case $1 in
            --target| -t)
                if [ "$2" == "local" ] || [ "$2" == "EKS" ] || [ "$2" == "Azure" ] || [ "$2" == "GCP" ]; then
                    opts["--target"]=$2
                    shift
                fi 
                ;;
            --no-deploy | -nd)
                opts["--no-deploy"]=true
                ;;
            --no-helmify | -nh)
                opts["--no-helmify"]=true
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}


helmify(){
    NAME=$1
    
    docker_run=$(yq e '.up.docker' $CURRENT_DIR/$NAME/scaffold.yaml)
    port=$(yq e '.project.port' $CURRENT_DIR/$NAME/scaffold.yaml)
    docker_repo=$(yq e '.project.docker-repo' $CURRENT_DIR/$NAME/scaffold.yaml)
    type=$(yq e '.project.type' $CURRENT_DIR/$NAME/scaffold.yaml)
    entry=$(yq e '.project.entry' $CURRENT_DIR/$NAME/scaffold.yaml)

    env_vars=$(yq e '.resources[].env-remote[]' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a env_vars <<< "$env_vars"

    secrets=()
    if [ -f $CURRENT_DIR/$NAME/".env" ]; then
        secrets+=($(cat $CURRENT_DIR/$NAME/".env"))
    fi

    if [ "$docker_run" == "null" ]; then
        print_warning "Docker Image is not built for $NAME component. Please build and push the image"
        return 1
    fi

    helmify_database(){
        NAME=$1
        wget https://github.com/rahulmedicharla/kubefs/archive/refs/heads/main.zip -O /tmp/repo.zip
        unzip -o /tmp/repo.zip "kubefs-main/scripts/templates/deployment/db/*" -d /tmp
        cp -r /tmp/kubefs-main/scripts/templates/deployment/db $CURRENT_DIR/$NAME/deploy
        rm -rf /tmp/repo.zip /tmp/kubefs-main

        wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/deployment/helm-values.conf -O "$CURRENT_DIR/$NAME/deploy/values.yaml"
        sed -i -e "s#{{NAME}}#$NAME#" \
            -i -e "s#{{IMAGE}}#cassandra#" \
            -i -e "s#{{PORT}}#$port#" \
            -i -e "s#{{TAG}}#latest#" \
            -i -e "s#{{SERVICE_TYPE}}#None#" \
            -i -e "s#{{ENTRY}}#$entry#" \
            "$CURRENT_DIR/$NAME/deploy/values.yaml"

        for env in "${env_vars[@]}"; do
            IFS='=' read -r -a env_parts <<< "$env"
            yq e ".env += [{\"name\" : \"${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
        done        
    }

    helmify_frontend(){
        NAME=$1

        wget https://github.com/rahulmedicharla/kubefs/archive/refs/heads/ingress.zip -O /tmp/repo.zip
        unzip -o /tmp/repo.zip "kubefs-ingress/scripts/templates/deployment/frontend/*" -d /tmp
        cp -r /tmp/kubefs-ingress/scripts/templates/deployment/frontend $CURRENT_DIR/$NAME/deploy
        rm -rf /tmp/repo.zip /tmp/kubefs-ingress

        wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/ingress/scripts/templates/deployment/helm-values.conf -O "$CURRENT_DIR/$NAME/deploy/values.yaml"
        sed -i -e "s#{{NAME}}#$NAME#" \
            -i -e "s#{{IMAGE}}#${docker_repo}#" \
            -i -e "s#{{PORT}}#80#" \
            -i -e "s#{{TAG}}#latest#" \
            -i -e "s#{{SERVICE_TYPE}}#LoadBalancer#" \
            -i -e "s#{{ENTRY}}#$entry#" \
            "$CURRENT_DIR/$NAME/deploy/values.yaml"
       
        for env in "${env_vars[@]}"; do
            IFS='=' read -r -a env_parts <<< "$env"
            yq e ".env += [{\"name\" : \"${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
        done
    }

    helmify_api(){
        NAME=$1
        wget https://github.com/rahulmedicharla/kubefs/archive/refs/heads/main.zip -O /tmp/repo.zip
        unzip -o /tmp/repo.zip "kubefs-main/scripts/templates/deployment/api/*" -d /tmp
        cp -r /tmp/kubefs-main/scripts/templates/deployment/api $CURRENT_DIR/$NAME/deploy
        rm -rf /tmp/repo.zip /tmp/kubefs-main

        wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/deployment/helm-values.conf -O "$CURRENT_DIR/$NAME/deploy/values.yaml"
        sed -i -e "s#{{NAME}}#$NAME#" \
            -i -e "s#{{IMAGE}}#${docker_repo}#" \
            -i -e "s#{{PORT}}#$port#" \
            -i -e "s#{{TAG}}#latest#" \
            -i -e "s#{{SERVICE_TYPE}}#ClusterIP#" \
            -i -e "s#{{ENTRY}}#$entry#" \
            "$CURRENT_DIR/$NAME/deploy/values.yaml"
        
        for env in "${env_vars[@]}"; do
            IFS='=' read -r -a env_parts <<< "$env"
            yq e ".env += [{\"name\" : \"${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
        done
    }
    
    case "$type" in
        "api") helmify_api $NAME;;
        "frontend") helmify_frontend $NAME;;
        "db") helmify_database $NAME;;
    esac

    if [ ${#secrets[@]} -gt 0 ]; then
        wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/deployment/shared/template-secret.conf -O $CURRENT_DIR/$NAME/deploy/templates/secret.yaml
        
        for secret in "${secrets[@]}"; do
            IFS='=' read -r -a secret_parts <<< "$secret"
            yq e ".secrets += [{\"name\" : \"${secret_parts[0]}\", \"value\": \"${secret_parts[1]}\", \"secretRef\": \"$NAME-deployment-secret\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
        done
    fi

    print_success "Helm Chart created for $NAME..."
}

deploy_all(){
    echo "Deploying all components..."
    CURRENT_DIR=`pwd`

    eval "$(parse_optional_params $@)"

    manifest_data=$(yq e '.resources[].name' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"


    if ! minikube status /dev/null 2>&1; then
        print_warning "minikube is not running. Starting minikube with 'minikube start'"
        minikube start

        kubectl get pods -n ingress-nginx | grep -q 1/1 && kubectl get pods -n local-path-storage | grep -q 1/1
        while [ $? -eq 1 ]; do
            print_warning "Waiting for minikube to finish setup..."
            sleep 2
            kubectl get pods -n ingress-nginx | grep -q 1/1 && kubectl get pods -n local-path-storage | grep -q 1/1
        done
    fi

    for name in "${manifest_data[@]}"; do

        deploy_unique $name "${opts[@]}"

        if [ $? -eq 1 ]; then
            print_error "Error occured deploying  $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    done

    print_success "Deployed all components"
    return 0
}

deploy_helper(){
    NAME=$1
    shift
    eval "$(parse_optional_params $@)"

    if ! minikube status > /dev/null 2>&1; then
        print_warning "minikube is not running. Starting minikube with 'minikube start'"
        minikube start

        kubectl get pods -n ingress-nginx | grep -q 1/1
        while [ $? -eq 1 ]; do
            print_warning "Waiting for minikube to finish setup..."
            sleep 2
            kubectl get pods -n ingress-nginx | grep -q 1/1
        done
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

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Deploying $NAME ..."

    case ${opts["--target"]} in
        # "EKS") deploy_eks $NAME;;
        # "Azure") deploy_azure $NAME;;
        # "GCP") deploy_gcp $NAME;;
        *)

            if [ "${opts["--no-helmify"]}" == false ]; then
                rm -rf $CURRENT_DIR/$NAME/deploy
                
                helmify $NAME

                if [ $? -eq 1 ]; then
                    print_error "Error occured helmifying $NAME. Please try again or use 'kubefs --help' for more information."
                    return 1
                fi
            fi

            if [ "${opts["--no-deploy"]}" == false ]; then

                helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy

                print_warning "Deployed $NAME... Use 'minikube tunnel' to port-forward the service to localhost"

                if [ $? -eq 1 ]; then
                    print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                    return 1
                fi
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