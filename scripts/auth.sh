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

    if [ -z $EMAIL ] || [ -z $PASSWORD ]; then
        echo "Email or password cannot be empty"
        default_helper 0
    fi

    if [ ! -f $SCRIPT_DIR/scripts/.env ]; then
        echo "Invalid Firebase API Key, please enter a valid key"
        return 1  
    fi

    # grab apikey
    apikey=$(cat $SCRIPT_DIR/scripts/.env | grep FIREBASE_API_KEY | cut -d '=' -f2)


    response=$(curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apikey" \
        -H "Content-Type: application/json" \
        --data-binary '{"email":"'"$EMAIL"'","password":"'"$PASSWORD"'","returnSecureToken":true}'
    )

    # Parse the response
    id_token=$(echo $response | jq -r '.idToken')
    refresh_token=$(echo $response | jq -r '.refreshToken')
    error_message=$(echo $response | jq -r '.error.message')
    expires_in=($(echo $response | jq -r '.expiresIn'))
    issued_at=$(date +%s)

    # Check if account creation was successful
    if [ "$id_token" != "null" ]; then
        echo ""
        echo "Login successfull!"

        auth_data=$(jq -n \
        --arg id_token "$id_token" \
        --arg refresh_token "$refresh_token" \
        --arg expires_in "$expires_in" \
        --arg issued_at "$issued_at" \
        '{id_token: $id_token, refresh_token: $refresh_token, expires_in: $expires_in, issued_at: $issued_at}')

        echo "$auth_data" | pass insert -f -m kubefs/auth
        
    else
        echo "Login failed: $error_message"
        echo "Please try again."
        return 1
    fi
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


