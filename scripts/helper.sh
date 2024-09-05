validate_project(){      
    if [ ! -f "`pwd`/manifest.yaml" ]; then
        print_warning "Error: Project not found. Please run 'kubefs init' to initialize project"
        return 1
    fi

    return 0
}

print_success(){
    echo -e "\033[0;32m$1\033[0m"
}

print_error(){
    echo -e "\033[0;31m$1\033[0m"
}

print_warning(){
    echo -e "\033[0;33m$1\033[0m"
}

append_to_manifest() {
    CURRENT_DIR=`pwd`
    NAME=$1
    ENTRY=$2
    PORT=$3
    COMMAND=$4
    TYPE=$5
    ADDRESS_LOCAL=$6
    ADDRESS_CLUSTER=$7
    UPPERCASE_NAME=$8

    sanitized_host=${UPPERCASE_NAME}_HOST
    sanitized_port=${UPPERCASE_NAME}_PORT
    print_warning "Use \"$sanitized_host\": \"$sanitized_port\" to access to access this resource."

    yq e ".resources += [{\"name\": \"$NAME\", \"entry\": \"$ENTRY\", \"port\": \"$PORT\", \"command\": \"$COMMAND\", \"type\": \"$TYPE\", \"env\": [\"$sanitized_host=$ADDRESS_LOCAL\", \"$sanitized_port=$PORT\"], \"env-remote\": [\"$sanitized_host=$ADDRESS_CLUSTER\", \"$sanitized_port=$PORT\"]}]" -i  $CURRENT_DIR/manifest.yaml
}

remove_from_manifest(){
    CURRENT_DIR=`pwd`
    NAME=$1

    yq e 'del(.resources[] | select(.name == "'$NAME'"))' -i $CURRENT_DIR/manifest.yaml
}