validate_project(){      
    if [ ! -f "`pwd`/manifest.kubefs" ]; then
        print_warning "Error: Project not found. Please run 'kubefs init' to initialize project"
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

print_success(){
    echo -e "\033[0;32m$1\033[0m"
}

print_error(){
    echo -e "\033[0;31m$1\033[0m"
}

print_warning(){
    echo -e "\033[0;33m$1\033[0m"
}

append_to_manifest() {
    CURRENT_DIR=`pwd`
    NAME=$1
    ENTRY=$2
    PORT=$3
    COMMAND=$4
    TYPE=$5

    echo "" >> $CURRENT_DIR/manifest.kubefs && echo "--" >> $CURRENT_DIR/manifest.kubefs
    echo "name=$NAME" >> $CURRENT_DIR/manifest.kubefs
    echo "entry=$ENTRY" >> $CURRENT_DIR/manifest.kubefs
    echo "port=$PORT" >> $CURRENT_DIR/manifest.kubefs
    echo "command=$COMMAND" >> $CURRENT_DIR/manifest.kubefs
    echo "type"=$TYPE >> $CURRENT_DIR/manifest.kubefs
}

remove_from_manifest(){
    CURRENT_DIR=`pwd`
    NAME=$1

    mapfile -t manifest_lines < "$CURRENT_DIR/manifest.kubefs"

    index=-1
    for i in "${!manifest_lines[@]}"; do
        if [[ "${manifest_lines[$i]}" == "name=$NAME" ]]; then
            index=$i
            break
        fi
    done

    if [[ $index -ne -1 ]]; then
        unset 'manifest_lines[$index+4]'
        unset 'manifest_lines[$index+3]'
        unset 'manifest_lines[$index+2]'
        unset 'manifest_lines[$index+1]'
        unset 'manifest_lines[$index]'
        unset 'manifest_lines[$index-1]'
        unset 'manifest_lines[$index-2]'
    fi

    printf "%s\n" "${manifest_lines[@]}" > "$CURRENT_DIR/manifest.kubefs"
}