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
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}

            describe_unique $name
            echo ""

            if [ $? -eq 1 ]; then
                print_error "Error occured describing $NAME. Please try again or use 'kubefs --help' or 'kubefs describe' for more information."
                return 0
            fi
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

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        print_error "$NAME is not a valid resource"
        default_helper
        return 1
    fi

    eval "$(parse_scaffold "$NAME")"

    for key in "${!scaffold_data[@]}"; do
        echo "$key: ${scaffold_data[$key]}"
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


