#!/bin/bash
default_helper() {
    echo "
    kubefs compile - easily create backend, frontend, & db resources to be used within your application

    Usage: kubefs create <COMMAND> [ARGS]
    kubefs create api <name> - creates a sample GET api called <name> using golang
    kubefs create frontend <name> - creates a sample frontend application called <name> using react
    kubefs create database <name> - creates a sample database called <name> using atlas

    Args:
        --port <port> - specify the port number for resource
        --entry <entry> - specify the entry [file (frontend or api) | keyspace (db)] for the resource
    "
}

validate_port(){
    CASE=$1

    ports=$(yq e '.resources[].port' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a ports <<< "$ports"

    for port in "${ports[@]}"; do
        if [ "$port" == "$CASE" ]; then
            return 1
        fi
    done
    
    return 0
}

parse_optional_params(){
    declare -A opts
    
    default_port=$1
    default_entry=$2
    shift 2

    opts["--port"]="$default_port"
    opts["--entry"]="$default_entry"

    while [ $# -gt 0 ]; do
        case $1 in
            --port)
                opts["--port"]=$2
                shift
                ;;
            --entry)
                opts["--entry"]=$2
                shift
                ;;
        esac
        shift
    done

    echo $(declare -p opts)
}

create_docker_repo(){
    NAME=$1
    echo "Creating Docker repository for $NAME..."

    output=$(pass show kubefs/config/docker > /dev/null 2>&1)

    if [ $? -eq 1 ]; then
        print_warning "Docker configurations not found. Please run 'kubefs config docker' to login to docker ecosystem"
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

    if [ $? -ne 0 ]; then
        print_error "Failed to login to Docker. Please try again."
        return 1
    fi

    token=$(echo $response | jq -r '.token')
    create_repo_response=$(curl -s -o /dev/null -w "%{http_code}" "https://hub.docker.com/v2/repositories/" \
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

    if [ "$create_repo_response" -ne 201 ]; then
        print_error "Failed to create Docker repository for $NAME. Please try again."
        return 1
    fi

    (cd "`pwd`/$NAME" && yq e ".project.docker-repo = \"$username/$NAME\"" "scaffold.yaml" -i)

    print_success "Docker repository for $NAME created successfully!"
    return 0
}

create_helper_func() {
    FUNC=$1
    TYPE=$2
    NAME=$3
    shift 3

    if [ -z $NAME ]; then
        default_helper
        return 0
    fi

    if [ -d "`pwd`/$NAME" ]; then
        print_warning "A component with name $NAME already exists, please try a different name"
        return 0
    fi

    NAME="$(yq e '.kubefs-name' "`pwd`/manifest.yaml")-$NAME"
    

    # call specified function
    echo "Creating $NAME..."
    $FUNC $NAME $@
    if [ $? -eq 1 ]; then
        print_error "Error occured creating $NAME. Please try again or use 'kubefs --help' for more information."
        rm -rf "`pwd`/$NAME"
        return 1
    fi

    case $TYPE in
        "api") 
            create_docker_repo $NAME
            if [ $? -eq 1 ]; then
                print_error "Error occured creating $NAME. Please try again or use 'kubefs --help' for more information."
                rm -rf "`pwd`/$NAME"
                remove_from_manifest $NAME
                return 1
            fi
            
            print_success "$TYPE $NAME was created successfully!"
            ;;
        "frontend")
            create_docker_repo $NAME
            if [ $? -eq 1 ]; then
                print_error "Error occured creating $NAME. Please try again or use 'kubefs --help' for more information."
                rm -rf "`pwd`/$NAME"
                remove_from_manifest $NAME
                return 1
            fi
            
            print_success "$TYPE $NAME was created successfully!"
            ;;
        "db") 
            print_success "$TYPE $NAME was created successfully!"
            ;;
    esac

    return 0
}

create_db(){
    NAME=$1
    CURRENT_DIR=`pwd`

    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "9042" "default" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    host=http://$(hostname -I | awk '{print $1}'):${opts["--port"]}
    
    mkdir $CURRENT_DIR/$NAME
    
    (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
    (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\"" $SCAFFOLD -i && yq e ".project.entry = \"${opts["--entry"]}\"" $SCAFFOLD -i && yq e ".project.port = \"${opts["--port"]}\"" $SCAFFOLD -i && yq e ".project.type = \"db\"" $SCAFFOLD -i )
    (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
    append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "" db "$host"

    return 0
}

create_api() {
    NAME=$1
    CURRENT_DIR=`pwd`
    
    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "8080" "main.go" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    mkdir $CURRENT_DIR/$NAME
    (cd $CURRENT_DIR/$NAME && go mod init $NAME && go get github.com/gorilla/mux)

    if [ $? -ne 0 ]; then
        return 1
    fi

    host=http://$(hostname -I | awk '{print $1}'):${opts["--port"]}

    sed -e "s/{{PORT}}/${opts["--port"]}/" \
        -e "s/{{NAME}}/$NAME/" \
        "$KUBEFS_CONFIG/scripts/templates/local-api/template-api.conf" > "$CURRENT_DIR/$NAME/${opts["--entry"]}"

    (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
    (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\"" $SCAFFOLD -i && yq e ".project.entry = \"${opts["--entry"]}\"" $SCAFFOLD -i && yq e ".project.port = \"${opts["--port"]}\"" $SCAFFOLD -i && yq e ".project.type = \"api\"" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"go run ${opts["--entry"]}\"" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
    append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "go run ${opts["--entry"]}" api "$host"

    return 0
}

create_frontend(){
    NAME=$1
    CURRENT_DIR=`pwd`

    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "3000" "index.js" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    mkdir $CURRENT_DIR/$NAME
    (cd $CURRENT_DIR/$NAME && npm init -y)
    (cd $CURRENT_DIR/$NAME && jq ".main = \"${opts["--entry"]}\"" package.json > tmp.json && mv tmp.json package.json)

    if [ $? -ne 0 ]; then
        return 1
    fi

    (cd `pwd`/$NAME && npm install express && npm install dotenv && npm install nodemon)

    if [ $? -ne 0 ]; then
        return 1
    fi

    host=http://$(hostname -I | awk '{print $1}'):${opts["--port"]}

    sed -e "s/{{NAME}}/$NAME/" \
        "$KUBEFS_CONFIG/scripts/templates/local-frontend/template-frontend.conf" > "$CURRENT_DIR/$NAME/${opts["--entry"]}"
    sed -e "s/{{PORT}}/$PORT/" \
        "$KUBEFS_CONFIG/scripts/templates/local-frontend/template-frontend-env.conf" > "$CURRENT_DIR/$NAME/.env"

    (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
    (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\"" $SCAFFOLD -i && yq e ".project.entry = \"${opts["--entry"]}\"" $SCAFFOLD -i && yq e ".project.port = \"${opts["--port"]}\"" $SCAFFOLD -i && yq e ".project.type = \"frontend\"" $SCAFFOLD -i )
    (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"nodemon ${opts["--entry"]}\"" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
    append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "nodemon ${opts["--entry"]}" frontend "$host"

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
        "api") create_helper_func create_api $COMMAND $@;;
        "frontend") create_helper_func create_frontend $COMMAND $@;;
        "database") create_helper_func create_db $COMMAND $@;;
        "--help") default_helper;;
        *) print_error "$COMMAND is not a valid command" && default_helper;;
    esac    
}
main $@
exit 0