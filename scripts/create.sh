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
        --framework | -f <framework>
            : specify the framework to use for frontend resource [react | vue | angular] default: react
            : specify the framework to use for api resource [express | go | fast] default: express 
            : specify the framework to use for db resource [mongo | cassandra] default: cassandra
    "
}

validate_port(){
    CASE=$1

    ports=$(yq e '.resources[].port' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a ports <<< "$ports"

    for port in "${ports[@]}"; do
        if [ "$port" == "$CASE" -o "$port" == "5000" -o "$port" == "6000" -o "$port" == "8000" ]; then
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
        remove_from_manifest $NAME
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
    print_warning "To utilize environment variables, populate a .env file in the $NAME directory"
    if [ ${opts["--type"]} == "frontend" ]; then
        print_warning "consume them in code using fetch("/env/{VARIABLE_NAME}")"
    fi
    echo ""

    return 0
}

create_db(){
    NAME=$1
    CURRENT_DIR=`pwd`

    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "9042" "default" "cassandra"$@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    local_host=localhost
    docker_host=$NAME-container-1
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local
    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )

    case ${opts["--framework"]} in
        "mongo")
            mkdir $CURRENT_DIR/$NAME
            (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
            (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"db\" | .project.framework=\"mongo\"" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
            append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "" db "$local_host" "$docker_host" "${cluster_host}" $sanitized_name
        ;;
        *)
            mkdir $CURRENT_DIR/$NAME
            (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
            (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"db\" | .project.framework=\"cassandra\"" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
            append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "" db "$local_host" "$docker_host" "${cluster_host}" $sanitized_name
        ;;
    esac
    return 0
}

create_api() {
    NAME=$1
    CURRENT_DIR=`pwd`
    
    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "8080" "main" "express" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi

    
    local_host=localhost
    docker_host=$NAME-traefik-1
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local
    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )

    case ${opts["--framework"]} in
        "fast")
            mkdir $CURRENT_DIR/$NAME
            (cd $CURRENT_DIR/$NAME && python3 -m venv venv && source venv/bin/activate && pip install fastapi uvicorn && deactivate)
            
            if [ $? -ne 0 ]; then
                return 1
            fi

            wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/local-api/template-api-fast.conf -O "$CURRENT_DIR/$NAME/${opts["--entry"]}.py"

            sed -i -e "s/{{NAME}}/$NAME/" \
                "$CURRENT_DIR/$NAME/${opts["--entry"]}.py"
            
            (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
            (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"api\" | .project.framework=\"fast\"" "$SCAFFOLD" -i)
            (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"source venv/bin/activate && uvicorn main:app --port ${opts["--port"]}\"" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
            append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "source venv/bin/activate && uvicorn main:app --port ${opts["--port"]}" api "$local_host" "$docker_host" "${cluster_host}" $sanitized_name

        ;;
        "go") 
            mkdir $CURRENT_DIR/$NAME
            (cd $CURRENT_DIR/$NAME && go mod init $NAME && go get github.com/gorilla/mux)

            if [ $? -ne 0 ]; then
                return 1
            fi

            wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/local-api/template-api.conf -O "$CURRENT_DIR/$NAME/${opts["--entry"]}.go"

            sed -i -e "s/{{PORT}}/${opts["--port"]}/" \
                -i -e "s/{{NAME}}/$NAME/" \
                "$CURRENT_DIR/$NAME/${opts["--entry"]}.go"

            (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
            (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"api\" | .project.framework=\"go\"" "$SCAFFOLD" -i)
            (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"go run ${opts["--entry"]}.go\"" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
            append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "go run ${opts["--entry"]}.go" api "$local_host" "$docker_host" "${cluster_host}" $sanitized_name        
        ;;
        *)
            mkdir $CURRENT_DIR/$NAME
            (cd $CURRENT_DIR/$NAME && npm init -y)

            if [ $? -ne 0 ]; then
                return 1
            fi

            (cd $CURRENT_DIR/$NAME && jq '.main = "'${opts["--entry"]}'" | .type = "module"' package.json > tmp.json && mv tmp.json package.json)
            (cd $CURRENT_DIR/$NAME && npm install express nodemon dotenv)

            if [ $? -ne 0 ]; then
                return 1
            fi

            wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/local-api/template-api-express.conf -O "$CURRENT_DIR/$NAME/${opts["--entry"]}.js"

            sed -i -e "s/{{NAME}}/$NAME/" \
                -i -e "s/{{PORT}}/${opts["--port"]}/" \
                "$CURRENT_DIR/$NAME/${opts["--entry"]}.js"

            (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
            (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"${opts["--entry"]}\" | .project.port = \"${opts["--port"]}\" | .project.type = \"api\" | .project.framework=\"express\"" "$SCAFFOLD" -i)
            (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"nodemon ${opts["--entry"]}.js\"" $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
            (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
            append_to_manifest $NAME "${opts["--entry"]}" "${opts["--port"]}" "nodemon ${opts["--entry"]}.js" api "$local_host" "$docker_host" "${cluster_host}" $sanitized_name        
        ;;
    esac
    return 0
}

create_frontend(){
    NAME=$1
    CURRENT_DIR=`pwd`

    SCAFFOLD=scaffold.yaml

    eval $(parse_optional_params "3000" "App.tsx" "react" $@)

    validate_port "${opts["--port"]}"
    if [ $? -eq 1 ]; then
        print_warning "Port ${opts["--port"]} is already in use, please use a different port"
        return 1
    fi
    
    local_host=localhost
    docker_host=$NAME-frontend-1
    cluster_host=$NAME-deployment.$NAME.svc.cluster.local
    sanitized_name=$(echo $NAME | tr '[:lower:]' '[:upper:]' | tr '-' '_' )

    if [ ${opts["--framework"]} == "angular" ]; then
        npm i -g @angular/cli
        if [ $? -ne 0 ]; then
            return 1
        fi

        ng new $NAME --defaults --skip-git
        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && npm i @ngx-env/builder)
        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && jq '.scripts.start = "ng serve --port '${opts["--port"]}'"' package.json > tmp.json && mv tmp.json package.json)
        (cd $CURRENT_DIR/$NAME && wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/local-frontend/template-angular-config.conf -O $CURRENT_DIR/$NAME/src/proxy.conf.json && jq '.projects["'$NAME'"].architect.serve.options.proxyConfig = "src/proxy.conf.json"' angular.json > tmp.json && mv tmp.json angular.json)
        
        (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
        (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"main.ts\" | .project.port = \"${opts["--port"]}\" | .project.type = \"frontend\" | .project.framework = \"angular\""  $SCAFFOLD -i )
        (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"npm run start\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
        append_to_manifest $NAME "main.ts" "${opts["--port"]}" "npm run start" frontend "$local_host" "$docker_host" "${cluster_host}" $sanitized_name

    elif [ ${opts["--framework"]} == "vue" ]; then
        npm create vue@latest $NAME -- --typescript
        if [ $? -ne 0 ]; then
            return 1
        fi

        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && npm i)
        (cd $CURRENT_DIR/$NAME && jq '.scripts.dev = "vite --port '${opts["--port"]}'"' package.json > tmp.json && mv tmp.json package.json)

        (cd $CURRENT_DIR/$NAME && rm -rf vite.config.ts && wget https://raw.githubusercontent.com/rahulmedicharla/kubefs/main/scripts/templates/local-frontend/template-vite-config.conf -O $CURRENT_DIR/$NAME/vite.config.ts)

        (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
        (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"App.vue\" | .project.port = \"${opts["--port"]}\" | .project.type = \"frontend\" | .project.framework = \"vue\""  $SCAFFOLD -i )
        (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"npm run dev\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
        append_to_manifest $NAME "App.vue" "${opts["--port"]}" "npm run dev" frontend "$local_host" "$docker_host" "${cluster_host}" $sanitized_name
    else
        (npx create-react-app@latest $NAME --no-git --template typescript)
        (cd $CURRENT_DIR/$NAME && rm -rf .git)

        if [ $? -ne 0 ]; then
            return 1
        fi

        (cd $CURRENT_DIR/$NAME && jq '.scripts.start = "export PORT='${opts["--port"]}' && react-scripts start" | .proxy = "http://localhost:5000"' package.json > tmp.json && mv tmp.json package.json)

        (cd $CURRENT_DIR/$NAME && touch $SCAFFOLD)
        (cd $CURRENT_DIR/$NAME && yq e ".project.name = \"$NAME\" | .project.entry = \"App.tsx\" | .project.port = \"${opts["--port"]}\" | .project.type = \"frontend\" | .project.framework = \"react\""  $SCAFFOLD -i )
        (cd $CURRENT_DIR/$NAME && yq e ".env = []" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e ".up.local = \"npm start\"" $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.local = ["rm -rf $CURRENT_DIR/$NAME", "remove_from_manifest $NAME"]' $SCAFFOLD -i)
        (cd $CURRENT_DIR/$NAME && yq e '.remove.remote = ["remove_repo $NAME"]' $SCAFFOLD -i)
        append_to_manifest $NAME "App.tsx" "${opts["--port"]}" "npm start" frontend "$local_host" "$docker_host" "${cluster_host}" $sanitized_name

    fi

    print_warning "Please enter the hostname to the frontend application: default is all hosts (*)"
    read hostname

    yq e ".project.hostname = \"$hostname\"" $CURRENT_DIR/$NAME/$SCAFFOLD -i

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