#!/bin/bash
default_helper() {
    echo "
    kubefs describe - describe the information about some or all of your resources

    Usage: kubefs describe <COMMAND>
        kubefs describe all - describe the information for all resources
        kubefs describe <name> - describe the information about the resources with given name
        kubefs describe --help - display this help message
    "
}

describe_all(){
    CURRENT_DIR=`pwd`

    manifest_data=$(yq e '.resources[].name' $CURRENT_DIR/manifest.yaml)
    IFS=$'\n' read -r -d '' -a manifest_data <<< "$manifest_data"

    for name in "${manifest_data[@]}"; do
        describe_unique $name
        echo ""

        if [ $? -eq 1 ]; then
            print_error "Error occured compiling $NAME. Please try again or use 'kubefs --help' for more information."
            return 1
        fi
    done

    return 0
}

describe_unique(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.yaml" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    project_info=$(yq e '.project' $CURRENT_DIR/$NAME/scaffold.yaml)
    IFS=$'\n' read -r -d '' -a project_info <<< "$project_info"

    for info in "${project_info[@]}"; do
        echo $info
    done

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
        "all")  describe_all;;
        "--help") default_helper;;
        *) describe_unique $COMMAND;;
    esac
}

main $@
exit 0


