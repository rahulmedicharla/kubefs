validate_project(){      
    if [ ! -f "`pwd`/manifest.kubefs" ]; then
        echo "You are not in a valid project folder, please initialize project using kubefs init or look at kubefs --help for more information"
        return 1
    fi
}

parse_manifest(){
    manifest_data=()
    while IFS= read -r line; do
        manifest_data+=("$line")
    done < "$1/manifest.kubefs"

    echo $(declare -p manifest_data)
}

parse_scaffold(){
    NAME=$1
    declare -A scaffold_data
    if [ ! -f "`pwd`/$NAME/scaffold.kubefs" ]; then
        echo "$NAME is not a valid project, please check the project name or look at kubefs --help for more information"
        return 1
    fi

    while IFS='=' read -r key value; do
        # Process the key-value pair here
        scaffold_data[$key]=$value
    done < "`pwd`/$NAME/scaffold.kubefs"

    echo $(declare -p scaffold_data)
}