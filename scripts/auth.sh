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
    apikey=$1

    echo "Enter your email: "
    read EMAIL
    echo "Enter your password: "
    read -s PASSWORD

    if [ -z $EMAIL ] || [ -z $PASSWORD ]; then
        echo "Email or password cannot be empty"
        default_helper 0
    fi

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
    uid=($(echo $response | jq -r '.localId'))

    # Check if account creation was successful
    if [ "$id_token" != "null" ]; then
        echo ""
        echo "Login successfull!"

        auth_data=$(jq -n \
        --arg id_token "$id_token" \
        --arg refresh_token "$refresh_token" \
        --arg expires_in "$expires_in" \
        --arg issued_at "$issued_at" \
        --arg uid "$uid" \
        '{id_token: $id_token, refresh_token: $refresh_token, expires_in: $expires_in, issued_at: $issued_at, uid: $uid}')

        echo "$auth_data" | pass insert -f -m kubefs/auth
        
    else
        echo "Login failed: $error_message"
        return 1
    fi
}

auth(){
    SCRIPT_DIR=$1

    if [ ! -f $SCRIPT_DIR/scripts/.env ]; then
        echo "Invalid Firebase API Key, please enter a valid key"
        return 1  
    fi

    apikey=$(cat $SCRIPT_DIR/scripts/.env | grep FIREBASE_API_KEY | cut -d '=' -f2)

    refresh_token=$(pass show kubefs/auth | jq -r '.refresh_token')

    if [ "$refresh_token" == "null" ]; then
        login $apikey
        return $?
    fi

    response=$(curl -s -X POST "https://securetoken.googleapis.com/v1/token?key=$apikey" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data "grant_type=refresh_token&refresh_token=$refresh_token"
    )

    id_token=$(echo $response | jq -r '.id_token')
    refresh_token=$(echo $response | jq -r '.refresh_token')
    error_message=$(echo $response | jq -r '.error.message')
    expires_in=($(echo $response | jq -r '.expires_in'))
    issued_at=$(date +%s)
    uid=($(echo $response | jq -r '.user_id'))

    if [ "$id_token" != "null" ]; then
        echo ""
        echo "Login successfull!"

        auth_data=$(jq -n \
        --arg id_token "$id_token" \
        --arg refresh_token "$refresh_token" \
        --arg expires_in "$expires_in" \
        --arg issued_at "$issued_at" \
        --arg uid "$uid" \
        '{id_token: $id_token, refresh_token: $refresh_token, expires_in: $expires_in, issued_at: $issued_at, uid: $uid}')

        echo "$auth_data" | pass insert -f -m kubefs/auth
        
    else
        echo "Login failed: $error_message"
        echo "Please try again."

        login $apikey
        return $?
    fi

}

main(){
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

    type=$1
    case $type in
        "login") auth $SCRIPT_DIR;;
        "--help") default_helper 0;;
        *) default_helper 1 $type;;
    esac    
}

main $@
exit 0


