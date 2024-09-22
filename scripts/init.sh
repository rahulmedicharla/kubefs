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

    mkdir env-api
    wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/shared/template-compose.conf -O $CURRENT_DIR/env-api/docker-compose.yaml
    sed -i -e "s#{{PORT}}#80#" \
        -i -e "s#{{HOST_PORT}}#5000#" \
        -i -e "s#{{NAME}}#rmedicharla/env-kubefs-api:latest#" \
        "$CURRENT_DIR/env-api/docker-compose.yaml"

    print_success "Successfully created $COMMAND project!"
}

init_project $@
exit 0
