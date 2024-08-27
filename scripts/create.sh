#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs create - easily create backend, frontend, & db constructs to be used within your application

    kubefs create api <name> - creates a sample GET api called <name> using golang
    kubefs create frontend <name> - creates a sample frontend application called <name> using react
    kubefs create database <name> - creates a sample database called <name> using atlas

    optional paramaters:
        -p <port> - specify the port number for the api (default is 8080)
        -e <entry_file> - specify the entry file for the api (default is main.go)
    "
}

parse_optional_params(){
    declare -A opts
    while getopts "p:e:" opt; do
        case ${opt} in
            p)
                opts["port"]=$OPTARG
                ;;
            e)
                opts["entry"]=$OPTARG
                ;;
            \? )
                echo "Invalid option: $OPTARG" 1>&2
                ;;
        esac
    done

    echo $(declare -p opts)
}

create_helper_func() {
    FUNC=$1
    NAME=$2
    shift 2

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 0
    fi

    if [ -d "`pwd`/$NAME" ]; then
        echo "A component with that name already exists, please try a different name"
        return 0
    fi

    eval $(parse_optional_params $@)

    # call specified function
    echo "Creating $NAME..."
    $FUNC $NAME
    if [ $? -eq 1 ]; then
        echo "Error occured creating $NAME. Please try again or use 'kubefs --help' for more information."
        rm -rf `pwd`/$NAME
        return 0
    fi
    
    output=$(pass show kubefs/config/docker > /dev/null 2>&1)

    if [ $? -eq 1 ]; then
        echo "Docker configurations not found. Please run 'kubefs config docker' to login to docker ecosystem"
        rm -rf `pwd`/$NAME
        return 1
    fi

    docker_auth=$(pass show kubefs/config/docker | jq -r '.')
    username=$(echo $docker_auth | jq -r '.username')
    password=$(echo $docker_auth | jq -r '.password')

    echo ""
    echo "Please enter a short description for the project:"
    read desc
    echo "Please enter a long description for the project:"
    read long_desc
    
    response=$(curl -s -X POST "https://hub.docker.com/v2/users/login/" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$username\", \"password\": \"$password\"}")

    token=$(echo $response | jq -r '.token')

    if [ -z $token ]; then
        echo "Failed to obtain Docker JWT token. Please try again."
        return 1
    fi

    create_repo_response=$(curl -s "https://hub.docker.com/v2/repositories/" \
        -H "Authorization: JWT $token" \
        -H "Content-Type: application/json" \
        --data "{
            \"description\": \"$desc\",
            \"full_description\": \"$long_desc\",
            \"is_private\": false,
            \"name\": \"$NAME\",
            \"namespace\": \"$username\" 
        }"
    )

    (cd `pwd`/$NAME && echo "docker-repo=$username/$NAME" >> scaffold.kubefs)
    
    echo ""
    echo "$NAME $FUNC was created successfully!"
    return 0
}

validate_port(){
    CASE=$1
    if grep -q "$CASE" "`pwd`/manifest.kubefs"; then
        return 1
    fi
    
    return 0
}

create_db(){
    NAME=$1

    PORT=27017

    if [ -n "${opts["port"]}" ]; then
        PORT=${opts["port"]}
    fi
    if [ -n "${opts["entry"]}" ]; then
        echo "You can not set the entry file for a database. Please try again."
        return 1
    fi    

    validate_port port=$PORT
    if [ $? -eq 1 ]; then
        echo "Port $PORT is already in use, please use a different port"
        return 1
    fi
    
    SCAFFOLD=scaffold.kubefs

    mkdir `pwd`/$NAME
    output=$(cd `pwd`/$NAME && atlas deployments setup $NAME --type local --port $PORT --connectWith skip --force)

    if [ $? -ne 0 ]; then
        return 1
    fi

    ENTRY=$(echo $output | grep -oP '(?<=Connection string: ).*')

    (cd `pwd`/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "command=atlas deployments start $NAME" >> $SCAFFOLD && echo "type=db" >> $SCAFFOLD)
    append_to_manifest $NAME $ENTRY $PORT "atlas deployments start $NAME" db

    return 0
}

create_api() {
    NAME=$1

    PORT=8080
    ENTRY=main.go

    if [ -n "${opts["port"]}" ]; then
        PORT=${opts["port"]}
    fi
    if [ -n "${opts["entry"]}" ]; then
        ENTRY=${opts["entry"]}
    fi    

    validate_port port=$PORT
    if [ $? -eq 1 ]; then
        echo "Port $PORT is already in use, please use a different port"
        return 1
    fi
    
    SCAFFOLD=scaffold.kubefs

    mkdir `pwd`/$NAME
    (cd `pwd`/$NAME && go mod init $NAME && go get github.com/gorilla/mux)

    if [ $? -ne 0 ]; then
        return 1
    fi

    sed -e "s/{{PORT}}/$PORT/" \
        -e "s/{{NAME}}/$NAME/" \
        "$KUBEFS_CONFIG/scripts/templates/template-api.conf" > "`pwd`/$NAME/$ENTRY"
    
    (cd `pwd`/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD && echo "command=go run $ENTRY" >> $SCAFFOLD && echo "type=api" >> $SCAFFOLD)
    append_to_manifest $NAME $ENTRY $PORT "go run $ENTRY" api

    return 0
}

create_frontend(){
    NAME=$1

    PORT=3000
    ENTRY=index.js

    if [ -n "${opts["port"]}" ]; then
        PORT=${opts["port"]}
    fi
    if [ -n "${opts["entry"]}" ]; then
        echo "You can not set the entry file for a frontend. Please try again."
        return 1
    fi    

    validate_port port=$PORT
    if [ $? -eq 1 ]; then
        echo "Port $PORT is already in use, please use a different port"
        return 1
    fi
    
    SCAFFOLD=scaffold.kubefs

    mkdir `pwd`/$NAME
    (cd `pwd`/$NAME && npm init -y)

    if [ $? -ne 0 ]; then
        echo "Error creating node.js/express application. Please try again."
        return 1
    fi

    (cd `pwd`/$NAME && npm install express && npm install dotenv && npm install nodemon && npm install handlab)
    
    if [ $? -ne 0 ]; then
        echo "Error creating node.js/express application. Please try again."
        return 1
    fi

    sed -e "s/{{NAME}}/$NAME/" \
        "$KUBEFS_CONFIG/scripts/templates/template-frontend.conf" > "`pwd`/$NAME/$ENTRY"
    sed -e "s/{{PORT}}/$PORT/" \
        "$KUBEFS_CONFIG/scripts/templates/template-frontend-env.conf" > "`pwd`/$NAME/.env"

    (cd `pwd`/$NAME && echo "name=$NAME" >> $SCAFFOLD && echo "entry=$ENTRY" >> $SCAFFOLD && echo "port=$PORT" >> $SCAFFOLD && echo "command=nodemon $ENTRY" >> $SCAFFOLD && echo "type=frontend" >> $SCAFFOLD)
    append_to_manifest $NAME $ENTRY $PORT "nodemon $ENTRY" frontend

    return 0
}

append_to_manifest() {
    CURRENT_DIR=`pwd`
    NAME=$1
    ENTRY=$2
    PORT=$3
    COMMAND=$4
    TYPE=$5

    echo "" >> $CURRENT_DIR/manifest.kubefs && echo "--" >> $CURRENT_DIR/manifest.kubefs
    echo "name=$NAME" >> $CURRENT_DIR/manifest.kubefs
    echo "entry=$ENTRY" >> $CURRENT_DIR/manifest.kubefs
    echo "port=$PORT" >> $CURRENT_DIR/manifest.kubefs
    echo "command=$COMMAND" >> $CURRENT_DIR/manifest.kubefs
    echo "type"=$TYPE >> $CURRENT_DIR/manifest.kubefs
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
        rm -rf `pwd`/$NAME
        return 0
    fi

    type=$1
    shift
    case $type in
        "api") create_helper_func create_api $@;;
        "frontend") create_helper_func create_frontend $@;;
        "database") create_helper_func create_db $@;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac    
}
main $@
exit 0