#!/bin/bash
default_helper() {
    echo "
    kubefs compile - easily create backend, frontend, & db resources to be used within your application

    Usage: kubefs create <COMMAND> [ARGS]
    kubefs create api <name> - creates a sample GET api called <name> using golang    
    kubefs create frontend <name> - creates a sample frontend application called <name>
    kubefs create database <name> - creates a sample database called <name> using atlas

    Args:
        --port | -p <port> - specify the port number for resource
        --entry | -e <entry> - specify the entry [file (frontend or api) | keyspace (db)] for the resource
        --framework | -f <framework> - 
            : specify the frontend framework to use [express.js | next.js | angular] | default: express.js 
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
    default_framework=$3
    shift 2

    opts["--port"]="$default_port"
    opts["--entry"]="$default_entry"
    opts["--framework"]="$default_framework"

    while [ $# -gt 0 ]; do
        case $1 in
            --port | -p)
                opts["--port"]=$2
                shift
                ;;
            --entry | -e)
                opts["--entry"]=$2
                shift
                ;;
            --framework | -f)
                opts["--framework"]=$2
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
            
            ;;
        "frontend")
            create_docker_repo $NAME
            if [ $? -eq 1 ]; then
                print_error "Error occured creating $NAME. Please try again or use 'kubefs --help' for more information."
                rm -rf "`pwd`/$NAME"
                remove_from_manifest $NAME
                return 1
            fi
            
            ;;
        "db") 
            ;;
    esac

    echo ""
    print_success "$NAME created successfully!"
    echo ""
    echo "To start the project use 'kubefs run $NAME'"
    echo ""
    print_warning "To utilize environment variables, create a .env file in the project directory"
    echo ""

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

    local_host=$(hostname -I | awk '{print $1}')
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local

    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )
    
    mkdir $CURRENT_DIR/$NAME
    
    (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
    (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\"" $SCAFFOLD -i && yq e ".project.entry = \"${opts["--entry"]}\"" $SCAFFOLD -i && yq e ".project.port = \"${opts["--port"]}\"" $SCAFFOLD -i && yq e ".project.type = \"db\"" $SCAFFOLD -i )
    (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
    append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "" db "$local_host" "${cluster_host}" $sanitized_name

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

    local_host=$(hostname -I | awk '{print $1}')
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local

    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )

    sed -e "s/{{PORT}}/${opts["--port"]}/" \
        -e "s/{{NAME}}/$NAME/" \
        "$KUBEFS_CONFIG/scripts/templates/local-api/template-api.conf" > "$CURRENT_DIR/$NAME/${opts["--entry"]}"

    (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
    (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\"" $SCAFFOLD -i && yq e ".project.entry = \"${opts["--entry"]}\"" $SCAFFOLD -i && yq e ".project.port = \"${opts["--port"]}\"" $SCAFFOLD -i && yq e ".project.type = \"api\"" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"go run ${opts["--entry"]}\"" $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
    (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
    append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "go run ${opts["--entry"]}" api "$local_host" "${cluster_host}" $sanitized_name

    return 0
}

create_frontend(){
    NAME=$1
    CURRENT_DIR=`pwd`

    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "3000" "index.js" "express.js" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    mkdir $CURRENT_DIR/$NAME
    
    local_host=$(hostname -I | awk '{print $1}')
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local
    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )

    if [ ${opts["--framework"]} == "next.js" ]; then
        (cd $CURRENT_DIR/$NAME && npx create-next-app --ts . )

        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && jq '.scripts.dev = "export PORT='${opts["--port"]}' && next dev" | .scripts.build = "export PORT='${opts["--port"]}' && next build" | .scripts.start = "export PORT='${opts["--port"]}' && next start" | .scripts.lint = "export PORT='${opts["--port"]}' && next lint"' package.json > tmp.json && mv tmp.json package.json)

        (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
        (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"page.tsx\" | .project.port = \"${opts["--port"]}\" | .project.type = \"frontend\" | .project.framework = \"next.js\""  $SCAFFOLD -i )
        (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"npm run dev\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
        append_to_manifest $NAME "page.tsx" "${opts["--port"]}" "npm run dev" frontend "$local_host" "${cluster_host}" $sanitized_name


    else
        (cd $CURRENT_DIR/$NAME && npm init -y)        
        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && jq '.main = "'${opts["--entry"]}'" | .type = "module"' package.json > tmp.json && mv tmp.json package.json)
        (cd `pwd`/$NAME && npm install express nodemon express-handlebars dotenv )

        if [ $? -ne 0 ]; then
            return 1
        fi
        
        sed -e "s/{{NAME}}/$NAME/" \
            -e "s/{{PORT}}/${opts["--port"]}/" \
            "$KUBEFS_CONFIG/scripts/templates/local-frontend/template-frontend.conf" > "$CURRENT_DIR/$NAME/${opts["--entry"]}"

        cp -r $KUBEFS_CONFIG/scripts/templates/local-frontend/views $CURRENT_DIR/$NAME/views

        (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
        (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"frontend\" | .project.framework = \"express.js\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"nodemon ${opts["--entry"]}\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
        append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "nodemon ${opts["--entry"]}" frontend "$local_host" "${cluster_host}" $sanitized_name

    fi
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