default_helper(){
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs init - initialize a new kubefs project

    kubefs init <name> - initialize a new kubefs project"
}

init_project() {
    output=$(pass show kubefs/config/docker > /dev/null 2>&1)

    if [ $? -eq 1 ]; then
        echo "Docker configurations not found. Please run 'kubefs config docker' to login to docker ecosystem"
        return 1
    fi

    docker_auth=$(pass show kubefs/config/docker | jq -r '.')
    username=$(echo $docker_auth | jq -r '.username')
    password=$(echo $docker_auth | jq -r '.password')

    echo "Please enter a project name:"
    read name
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
            \"is_private\": true,
            \"name\": \"$name\",
            \"namespace\": \"$username\" 
        }"
    )

    mkdir $name && cd $name

    touch manifest.kubefs
    echo "KUBEFS_NAME=$name" >> manifest.kubefs && echo "KUBEFS_ROOT=`pwd`" >> manifest.kubefs

    echo "Successfully created $name project"
}

init_project
exit 0
