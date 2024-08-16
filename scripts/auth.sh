#!/bin/bash
default_helper() {
    TYPE=$1
    if [ $TYPE -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs auth - authenticate into your kubefs account
    kubefs auth login <email> <password> - login to your kubefs account
    "
}

login(){
    EMAIL=$1
    PASSWORD=$2

    echo "Logging in..."
    echo "Email: $EMAIL"
    echo "Password: $PASSWORD"
}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    type=$1
    email=$2
    password=$3
    case $type in
        "login") login $email $password;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac    
}

main $@
exit 0


