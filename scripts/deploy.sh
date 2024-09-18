#!/bin/bash
default_helper() {
    echo "
    kubefs deploy - create helm charts & deploy the build targets onto the cluster

    Usage: kubefs deploy <COMMAND> [ARGS]
        kubefs deploy all - deploy all built components onto specified clusters
        kubefs deploy <name> - deploy specified component onto cluster
        kubefs deploy --help - display this help message

        Args:
            --target | -t <local|aws|azure|google> - specify the deployment target for which cluster (default is local)
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
                if [ "$2" == "local" ] || [ "$2" == "aws" ] || [ "$2" == "azure" ] || [ "$2" == "google" ]; then
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
    framework=$(yq e '.project.framework' $CURRENT_DIR/$NAME/scaffold.yaml)

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
        case $framework in
            "mongo")
                rm -rf $CURRENT_DIR/$NAME/deploy/templates/statefulset-cassandra.yaml
                mv $CURRENT_DIR/$NAME/deploy/templates/statefulset-mongo.yaml $CURRENT_DIR/$NAME/deploy/templates/statefulset.yaml
                sed -i -e "s#{{NAME}}#$NAME#" \
                    -i -e "s#{{IMAGE}}#mongo#" \
                    -i -e "s#{{PORT}}#$port#" \
                    -i -e "s#{{TAG}}#latest#" \
                    -i -e "s#{{SERVICE_TYPE}}#None#" \
                    -i -e "s#{{ENTRY}}#$entry#" \
                    -i -e "s#{{HOST}}#\"\"#" \
                    -i -e "s#{{PATH}}#\"\"#" \
                    "$CURRENT_DIR/$NAME/deploy/values.yaml"
                ;;
            *)
                rm -rf $CURRENT_DIR/$NAME/deploy/templates/statefulset-mongo.yaml
                mv $CURRENT_DIR/$NAME/deploy/templates/statefulset-cassandra.yaml $CURRENT_DIR/$NAME/deploy/templates/statefulset.yaml
                sed -i -e "s#{{NAME}}#$NAME#" \
                    -i -e "s#{{IMAGE}}#cassandra#" \
                    -i -e "s#{{PORT}}#$port#" \
                    -i -e "s#{{TAG}}#latest#" \
                    -i -e "s#{{SERVICE_TYPE}}#None#" \
                    -i -e "s#{{ENTRY}}#$entry#" \
                    -i -e "s#{{HOST}}#\"\"#" \
                    -i -e "s#{{PATH}}#\"\"#" \
                    "$CURRENT_DIR/$NAME/deploy/values.yaml"
                ;; 
        esac

        for env in "${env_vars[@]}"; do
            IFS='=' read -r -a env_parts <<< "$env"
            yq e ".env += [{\"name\" : \"${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
        done        
    }

    helmify_frontend(){
        NAME=$1
        hostname=$(yq e '.project.hostname' $CURRENT_DIR/$NAME/scaffold.yaml)
        path=$(yq e '.project.path' $CURRENT_DIR/$NAME/scaffold.yaml)

        if [ "$hostname" == "null" ]; then
            hostname=""
        fi

        wget https://github.com/rahulmedicharla/kubefs/archive/refs/heads/main.zip -O /tmp/repo.zip
        unzip -o /tmp/repo.zip "kubefs-main/scripts/templates/deployment/frontend/*" -d /tmp
        cp -r /tmp/kubefs-main/scripts/templates/deployment/frontend $CURRENT_DIR/$NAME/deploy
        rm -rf /tmp/repo.zip /tmp/kubefs-main

        wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/deployment/helm-values.conf -O "$CURRENT_DIR/$NAME/deploy/values.yaml"
        sed -i -e "s#{{NAME}}#$NAME#" \
            -i -e "s#{{IMAGE}}#${docker_repo}#" \
            -i -e "s#{{PORT}}#80#" \
            -i -e "s#{{TAG}}#latest#" \
            -i -e "s#{{SERVICE_TYPE}}#LoadBalancer#" \
            -i -e "s#{{ENTRY}}#$entry#" \
            -i -e "s#{{HOST}}#$hostname#" \
            -i -e "s#{{PATH}}#$path#" \
            "$CURRENT_DIR/$NAME/deploy/values.yaml"
       
        for env in "${env_vars[@]}"; do
            IFS='=' read -r -a env_parts <<< "$env"
            case $framework in 
                "angular")
                    yq e ".env += [{\"name\" : \"NG_APP_${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                    ;;
                "vue")
                    yq e ".env += [{\"name\" : \"VUE_APP_${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                    ;;
                *)
                    yq e ".env += [{\"name\" : \"REACT_APP_${env_parts[0]}\", \"value\": \"${env_parts[1]}\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                    ;;
            esac
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
            -i -e "s#{{HOST}}#\"\"#" \
            -i -e "s#{{PATH}}#\"\"#" \
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
            if [ "$type" == "frontend" ]; then
                case $framework in 
                    "angular")
                        yq e ".secrets += [{\"name\" : \"NG_APP_${secret_parts[0]}\", \"value\": \"${secret_parts[1]}\", \"secretRef\": \"$NAME-deployment-secret\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                        ;;
                    "vue")
                        yq e ".secrets += [{\"name\" : \"VUE_APP_${secret_parts[0]}\", \"value\": \"${secret_parts[1]}\", \"secretRef\": \"$NAME-deployment-secret\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                        ;;
                    *)
                        yq e ".secrets += [{\"name\" : \"NEXT_PUBLIC_${secret_parts[0]}\", \"value\": \"${secret_parts[1]}\", \"secretRef\": \"$NAME-deployment-secret\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
                        ;;
                esac
            else
                yq e ".secrets += [{\"name\" : \"${secret_parts[0]}\", \"value\": \"${secret_parts[1]}\", \"secretRef\": \"$NAME-deployment-secret\"}]" $CURRENT_DIR/$NAME/deploy/values.yaml -i
            fi
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

    deploy_unique $NAME "${opts[@]}"

    if [ $? -eq 1 ]; then
        print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
        return 0
    fi

    return 0
}

deploy_google(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Deploying $NAME ..."
    if [ "${opts["--no-helmify"]}" == false ]; then
        rm -rf $CURRENT_DIR/$NAME/deploy
        
        helmify $NAME

        if [ $? -eq 1 ]; then
            print_error "Error occured helmifying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    fi

    if [ "${opts["--no-deploy"]}" == false ]; then
        if ! gcloud auth list --format="value(account)" | grep -q "@"; then
            print_warning "Google Cloud account not logged in. Please login using 'gcloud auth login'"
            return 1
        fi

        if ! gcloud services list --enabled --format="value(config.name)" | grep -q "container.googleapis.com"; then
            print_warning "GKE API not enabled. Enabling GKE API..."
            gcloud services enable container.googleapis.com
            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
            print_success "GKE API enabled successfully"
        fi

        if ! gcloud container clusters list --format="value(name)" | grep -q $(yq e '.google.cluster_name' $CURRENT_DIR/manifest.yaml); then
            print_warning "GKE cluster does not exist. Creating GKE cluster..."
            gcloud container clusters create-auto $(yq e '.google.cluster_name' $CURRENT_DIR/manifest.yaml) --region=$(yq e '.google.region' $CURRENT_DIR/manifest.yaml)
            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
            print_success "GKE cluster $(yq e '.google.cluster_name' $CURRENT_DIR/manifest.yaml) created successfully"
        fi

        if ! gcloud components list --format="value(name)"| grep -q "gke-gcloud-auth-plugin"; then
            print_warning "GKE gcloud auth plugin not installed. Installing GKE cloud auth plugin..."
            gcloud components install gke-gcloud-auth-plugin
            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
            print_success "GKE cloud auth plugin installed successfully"
        fi

        gcloud container clusters get-credentials $(yq e '.google.cluster_name' $CURRENT_DIR/manifest.yaml) --region $(yq e '.google.region' $CURRENT_DIR/manifest.yaml)
        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi

        while [ $(kubectl get nodes | grep -c NotReady) -gt 0 ]; do
            print_warning "Waiting for GKE cluster to finish setup..."
            sleep 2
        done

        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        
        NAMESPACE=metrics-server
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml     
            kubectl wait --for=condition=available --timeout=5m deployment/metrics-server
        fi  
  
        NAMESPACE=ingress-nginx
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            helm install ingress-nginx ingress-nginx/ingress-nginx \
                --create-namespace \
                --namespace $NAMESPACE \
                --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
                --set controller.service.externalTrafficPolicy=Local
            kubectl wait --for=condition=available --timeout=5m deployment/ingress-nginx-controller -n ingress-nginx
        fi

        helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy

        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    fi

    return 0
}

deploy_azure(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Deploying $NAME ..."
    if [ "${opts["--no-helmify"]}" == false ]; then
        rm -rf $CURRENT_DIR/$NAME/deploy
        
        helmify $NAME

        if [ $? -eq 1 ]; then
            print_error "Error occured helmifying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    fi

    if [ "${opts["--no-deploy"]}" == false ]; then

        if ! az account show > /dev/null 2>&1; then
            print_warning "Azure account not logged in. Please login using 'kubefs config azure'"
            return 1
        fi

        if ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Compute; then
            print_warning "Azure Compute provider not registered. Registering provider..."
            az provider register --namespace Microsoft.Compute
            while ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Compute; do
                print_warning "Waiting for provider to finish registration..."
                sleep 2
            done
            print_success "Azure Compute provider registered successfully"
        fi

        if ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.ContainerService; then
            print_warning "Azure ContainerService provider not registered. Registering provider..."
            az provider register --namespace Microsoft.ContainerService
            while ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.ContainerService; do
                print_warning "Waiting for provider to finish registration..."
                sleep 2
            done
            print_success "Azure ContainerService provider registered successfully"
        fi

        if ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Network; then
            print_warning "Azure Network provider not registered. Registering provider..."
            az provider register --namespace Microsoft.Network
            while ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Network; do
                print_warning "Waiting for provider to finish registration..."
                sleep 2
            done
            print_success "Azure Network provider registered successfully"
        fi

        if ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Storage; then
            print_warning "Azure Storage provider not registered. Registering provider..."
            az provider register --namespace Microsoft.Storage
            while ! az provider list --query "[?registrationState=='Registered']" --output table | grep -q Microsoft.Storage; do
                print_warning "Waiting for provider to finish registration..."
                sleep 2
            done
            print_success "Azure Storage provider registered successfully"
        fi

        if az group exists --name "$(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml)" | grep -q "false"; then
            print_warning "Resource group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) does not exist. Creating resource group..."
            az group create --name "$(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml)" --region "$(yq e '.azure.region' $CURRENT_DIR/manifest.yaml)"

            if [ $? -eq 1 ]; then
                print_error "Error occurred deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi

            az group wait --name "$(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml)" --created
            print_success "Resource group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) created successfully"
        fi

        if ! az aks list -o table | grep -q $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml); then
            print_warning "AKS cluster does not exist. Creating AKS cluster..."
            az aks create --resource-group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) --name $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml) --node-count 1 --generate-ssh-keys

            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi

            print_success "AKS cluster $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml) created successfully"
        fi

        if az aks show --resource-group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) --name $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml) --query "powerState.code" -o tsv | grep -q "Stopped" ; then
            print_warning "AKS cluster is not started. Starting AKS cluster..."

            az aks start --resource-group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) --name $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml)
            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
        fi

        az aks get-credentials --resource-group $(yq e '.azure.resource_group' $CURRENT_DIR/manifest.yaml) --name $(yq e '.azure.cluster_name' $CURRENT_DIR/manifest.yaml)
        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi

        while [ $(kubectl get nodes | grep -c NotReady) -gt 0 ]; do
            print_warning "Waiting for cluster to finish setup..."
            sleep 2
        done

        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        
        NAMESPACE=metrics-server
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
            kubectl wait --for=condition=available --timeout=5m deployment/metrics-server         
        fi  
  
        NAMESPACE=ingress-nginx
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            helm install ingress-nginx ingress-nginx/ingress-nginx \
                --create-namespace \
                --namespace $NAMESPACE \
                --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
                --set controller.service.externalTrafficPolicy=Local
            kubectl wait --for=condition=available --timeout=5m deployment/ingress-nginx-controller -n ingress-nginx
        fi

        helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy

        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi

    fi

    print_success "$NAME deployed successfully"
    return 0
}

deploy_aws(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    echo "Deploying $NAME ..."
    if [ "${opts["--no-helmify"]}" == false ]; then
        rm -rf $CURRENT_DIR/$NAME/deploy
        
        helmify $NAME

        if [ $? -eq 1 ]; then
            print_error "Error occured helmifying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    fi

    if [ "${opts["--no-deploy"]}" == false ]; then

        if ! aws sts get-caller-identity > /dev/null 2>&1; then
            print_warning "AWS account not logged in. Please login using 'kubefs config aws'"
            return 1
        fi

        if ! eksctl get cluster --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml) | grep -q $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml); then
            print_warning "EKS cluster does not exist. Creating EKS cluster..."
            eksctl create cluster --name $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml) --node-type t2.micro --nodes-min 1 --nodes-max 5 --managed

            if [ $? -eq 1 ]; then
                print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                return 1
            fi
            print_success "EKS cluster $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) created successfully"
        fi

        eksctl utils write-kubeconfig --cluster $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml)

        if [ $(eksctl get nodegroup --cluster $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml) -o json | jq -r '.[].DesiredCapacity') == 0 ]; then
            print_warning "EKS not running. Starting EKS cluster..."
            for nodegroup in $(eksctl get nodegroup --cluster $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml) --output json | jq -r '.[].Name'); do
                eksctl scale nodegroup --region $(yq e '.aws.region' $CURRENT_DIR/manifest.yaml) --cluster $(yq e '.aws.cluster_name' $CURRENT_DIR/manifest.yaml) --name $nodegroup --nodes-min 1 --nodes-max 5
            done
        fi

        while [ $(kubectl get nodes | grep -c NotReady) -gt 0 ]; do
            print_warning "Waiting for EKS cluster to finish setup..."
            sleep 2
        done

        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        
        NAMESPACE=metrics-server
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml       
            kubectl wait --for=condition=available --timeout=5m deployment/metrics-server
        fi  
  
        NAMESPACE=ingress-nginx
        if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
            helm install ingress-nginx ingress-nginx/ingress-nginx \
                --create-namespace \
                --namespace $NAMESPACE \
                --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
                --set controller.service.externalTrafficPolicy=Local
            kubectl wait --for=condition=available --timeout=5m deployment/ingress-nginx-controller -n ingress-nginx
        fi

        helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy

        if [ $? -eq 1 ]; then
            print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi

    fi

    print_success "$NAME deployed successfully"
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

    echo "Deploying $NAME to ${opts["--target"]}..."

    case ${opts["--target"]} in
        "aws") deploy_aws $NAME
            if [ $? -eq 1 ]; then
                return 1
            fi
            ;;
        "azure")
            deploy_azure $NAME
            if [ $? -eq 1 ]; then
                return 1
            fi 
            ;;
        "google") 
            deploy_google $NAME
            if [ $? -eq 1 ]; then
                return 1
            fi
            ;;
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
                if ! minikube status > /dev/null 2>&1; then
                    print_warning "minikube is not running. Starting minikube with 'minikube start'"
                    minikube start
                    kubectl config use-context minikube

                    kubectl get pods -n ingress-nginx | grep -q 1/1
                    while [ $? -eq 1 ]; do
                        print_warning "Waiting for minikube to finish setup..."
                        sleep 2
                        kubectl get pods -n ingress-nginx | grep -q 1/1
                    done
                else
                    kubectl config use-context minikube
                fi

                helm upgrade --install $NAME $CURRENT_DIR/$NAME/deploy

                print_warning "Deployed $NAME... Use 'minikube tunnel' or 'minikube service -n $NAME $NAME-deployment --url' to port-forward the service to localhost"

                if [ $? -eq 1 ]; then
                    print_error "Error occured deploying $NAME. Please try again or use 'kubefs --help' for more information."
                    return 1
                fi
            fi
            return 0
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