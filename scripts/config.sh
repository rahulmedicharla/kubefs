# #!/bin/bash
# default_helper() {
#     if [ $1 -eq 1 ]; then
#         echo "${2} is not a valid argument, please follow types below"
#     fi

#     echo "
#     kubefs config - customzie your project congifurations

#     kubefs config list - list all configurations
#     "
# }

# list_configurations(){
#     echo "MongoDB configurations"
#     pass show kubefs/config/mongo
# }


# # Check if GPG key exists
# if ! gpg --list-keys | grep -q "pub"; then
#     echo "No GPG key found. Generating a new GPG key..."
#     gpg --full-generate-key
# fi

# # List keys and get the key ID
# key_id=$(gpg --list-keys | grep -A 1 "pub" | tail -n 1 | awk '{print $1}')

# # Initialize pass with the GPG key
# pass init "$key_id"

# auth_data=$(jq -n \
# --arg setup "$id_token" \
# --arg expires_in "$expires_in" \
# --arg issued_at "$issued_at" \
# --arg uid "$uid" \
# --arg refresh_token "$refresh_token" \
# '{id_token: $id_token, expires_in: $expires_in, issued_at: $issued_at, uid: $uid, refresh_token: $refresh_token}')

# echo "$auth_data" | pass insert -m kubefs/auth

# if [ $? -eq 1 ]; then
#     echo "Account creation failed. Please try again."
#     return 1
# fi


main $@
exit 0


