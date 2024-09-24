default_helper(){
    echo "
    kubefs init - initialize a new kubefs project

    Usage: kubefs init <COMMAND>
        kubefs init <name> - initialize a new kubefs project
    "
}

init_project() {
    COMMAND=$1
    if [ -z $COMMAND ]; then
        default_helper
        return 1
    fi

    source $KUBEFS_CONFIG/scripts/helper.sh

    echo "Creating $COMMAND project..."
    echo "Please enter a description for the project: "
    read DESCRIPTION

    mkdir $COMMAND && cd $COMMAND

    touch manifest.yaml
    yq e ".kubefs-name = \"${COMMAND}\"" -i manifest.yaml
    yq e ".kubefs-version = \"0.0.1\"" -i manifest.yaml
    yq e ".kubefs-description = \"${DESCRIPTION}\"" -i manifest.yaml
    yq e ".resources = []" -i manifest.yaml

    wget https://github.com/rahulmedicharla/env-kubefs-api/archive/refs/heads/main.zip -O kubefs-api.zip
    unzip kubefs-api.zip -d env-kubefs-api
    mv env-kubefs-api/env-kubefs-api-main/* env-kubefs-api
    rm -rf kubefs-api.zip env-kubefs-api/env-kubefs-api-main

    print_success "Successfully created $COMMAND project!"
}

init_project $@
exit 0
