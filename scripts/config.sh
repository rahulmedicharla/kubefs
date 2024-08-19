#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs config - customzie your project congifurations

    kubefs config mongo - set your mongodb username and password
    kubefs config list - list all configurations
    "
}

configure_mongo(){
    echo "Please enter your username"
    read username
    echo "Please enter your password"
    read -s password

    mongo_data=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        '{username: $username, password: $password}'
    )

    echo "$mongo_data" | pass insert -f -m kubefs/config/mongo

    echo "MongoDB configurations saved successfully"
}

list_configurations(){
    echo "MongoDB configurations"
    pass show kubefs/config/mongo
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    if [ -z $1 ]; then
        default_helper 0
        return 1
    fi

    # source helper functions 
    source $SCRIPT_DIR/scripts/helper.sh
    validate_project

    type=$1
    case $type in
        "mongo") configure_mongo;;
        "list") list_configurations;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac
}

main $@
exit 0


