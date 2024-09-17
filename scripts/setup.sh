#!/bin/bash
default_helper() {
    echo "
    kubefs setup - download dependencies & setup configurations for first time.
    
    Usage: kubefs setup
    "
}

download_dependencies(){
    echo "Setting up kubefs configurations for the first time..."
    echo "Verifying dependencies..."

    if !(command -v brew &> /dev/null); then
        echo "Installing homebrew package manager..."
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)";
        test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
    fi

    #Downloading go if not downloaded
    if !(command -v go &> /dev/null); then
        echo "Installing go..."
        mkdir $HOME/go
        echo "" >> ~/.bashrc && echo '''export GOPATH=$HOME/go''' >> ~/.bashrc
        echo '''export GOROOT="$(brew --prefix golang)/libexec"''' >> ~/.bashrc
        echo '''export PATH="$PATH:${GOPATH}/bin:${GOROOT}/bin"''' >> ~/.bashrc
        source ~/.bashrc
        brew install go

        if [ $? -ne 0 ]; then
            echo "Failed to install go. Exiting..."
            return 1
        fi
    fi

    #Downloading python if not downloaded
    if !(command -v python3 &> /dev/null); then
        echo "Installing python..."
        brew install python

        if [ $? -ne 0 ]; then
            echo "Failed to install python. Exiting..."
            return 1
        fi
    fi

    # prompt to download minikube
    if !(command -v minikube &> /dev/null); then
        echo "Downloading minikube..."
        brew install minikube

        if [ $? -ne 0 ]; then
            echo "Failed to install minikube. Exiting..."
            return 1
        fi

        minikube start
        minikube addons enable ingress
        minikube addons enable metrics-server
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
        minikube stop
    fi

    # prompt to download docker
    if !(command -v docker &> /dev/null); then
        echo "Downloading docker..."
        brew install docker

        if [ $? -ne 0 ]; then
            echo "Failed to install docker. Exiting..."
            return 1
        fi
    fi 

    if !(command -v docker compose &> /dev/null); then
        echo "Downloading docker compose..."
        brew install docker-compose

        if [ $? -ne 0 ]; then
            echo "Failed to install docker-compose. Exiting..."
            return 1
        fi
    fi

    if !(command -v node &> /dev/null); then
        echo "Downloading node..."
        brew install node

        if [ $? -ne 0 ]; then
            echo "Failed to install node. Exiting..."
            return 1
        fi
    fi

    if !(command -v cassandra &> /dev/null); then
        echo "Downloading cassandra..."
        brew install cassandra

        if [ $? -ne 0 ]; then
            echo "Failed to install cassandra. Exiting..."
            return 1
        fi
    fi

    if !(command -v mongosh &> /dev/null); then
        echo "Downloading mongosh..."
        brew tap mongodb/brew
        brew install mongosh

        if [ $? -ne 0 ]; then
            echo "Failed to install mongosh. Exiting..."
            return 1
        fi
    fi

    if !(command -v jq &> /dev/null); then
        echo "Downloading jq..."
        brew install jq

        if [ $? -ne 0 ]; then
            echo "Failed to install jq. Exiting..."
            return 1
        fi
    fi

    if !(command -v yq &> /dev/null); then
        echo "Downloading yq..."
        brew install yq

        if [ $? -ne 0 ]; then
            echo "Failed to install yq. Exiting..."
            return 1
        fi
    fi

    if !(command -v curl &> /dev/null); then
        echo "Downloading curl..."
        brew install curl

        if [ $? -ne 0 ]; then
            echo "Failed to install curl. Exiting..."
            return 1
        fi
    fi

    if !(command gpg &> /dev/null); then
        echo "Downloading gpg..."
        brew install gnupg

        if [ $? -ne 0 ]; then
            echo "Failed to install gpg. Exiting..."
            return 1
        fi
    fi

    if !(command -v pass &> /dev/null); then
        echo "Downloading pass..."
        brew install pass

        if [ $? -ne 0 ]; then
            echo "Failed to install pass. Exiting..."
            return 1
        fi
    fi

    if !(command -v helm &> /dev/null); then
        echo "Downloading helm..."
        brew install helm

        if [ $? -ne 0 ]; then
            echo "Failed to install helm. Exiting..."
            return 1
        fi
    fi

    if !(command -v kubectl &> /dev/null); then
        echo "Downloading kubectl..."
        brew install kubectl

        if [ $? -ne 0 ]; then
            echo "Failed to install kubectl. Exiting..."
            return 1
        fi
    fi

    if !(command -v az &> /dev/null); then
        echo "Downloading azure-cli..."
        brew install azure-cli

        if [ $? -ne 0 ]; then
            echo "Failed to install azure-cli. Exiting..."
            return 1
        fi
    fi

    if !(command -v gcloud &> /dev/null); then
        echo "Downloading gcloud..."
        (cd ~ && curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz;
        tar -xf google-cloud-cli-linux-x86_64.tar.gz;
        sh ./google-cloud-sdk/install.sh;
        )

        if [ $? -ne 0 ]; then
            echo "Failed to install gcloud. Exiting..."
            return 1
        fi
    fi

    if !(command -v aws &> /dev/null); then
        echo "Downloading aws-cli..."
        brew install awscli

        if [ $? -ne 0 ]; then
            echo "Failed to install aws-cli. Exiting..."
            return 1
        fi
    fi

    if !(command -v eksctl &> /dev/null); then
        echo "Downloading eksctl..."
        brew install eksctl
        if [ $? -ne 0 ]; then
            echo "Failed to install eksctl. Exiting..."
            return 1
        fi
    fi
}

init_project() {
    SCRIPT_DIR=$1
    source $SCRIPT_DIR/scripts/helper.sh

    if [ ! -z $KUBEFS_CONFIG ]; then
        print_warning "Kubefs has already been setup. use 'kubefs --help' for more information"
        return 0
    fi

    if grep -q "export KUBEFS_CONFIG" ~/.bashrc; then
        print_warning "Kubefs has already been setup. run 'source ~/.bashrc' to start using kubefs"
        return 0
    fi

    download_dependencies

    if [ $? -ne 0 ]; then
        echo "Failed to download dependencies. Exiting..."
        return 1
    fi

    echo "export KUBEFS_CONFIG="$SCRIPT_DIR"" >> ~/.bashrc

    echo "" && echo "Account creation successful!"
    echo "Please run 'source ~/.bashrc' to start using kubefs"
    return 0
        
}

main(){
    SCRIPT_DIR=$1
    init_project $SCRIPT_DIR
}

main $@
exit 0


