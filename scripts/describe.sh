#!/bin/bash
default_helper() {
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs describe - describe the information about some or all of your constructs

    kubefs describe all - describe the information for all constructs
    kubefs describe <name> - describe the information about the construct with given name
    "
}

describe_all(){
    CURRENT_DIR=`pwd`
    eval "$(parse_manifest $CURRENT_DIR)"

    for ((i=0; i<${#manifest_data[@]}; i++)); do
        if [ "${manifest_data[$i]}" == "--" ]; then
            name=${manifest_data[$i+1]#*=}
            entry=${manifest_data[$i+2]#*=}
            port=${manifest_data[$i+3]#*=}
            command=${manifest_data[$i+4]#*=}
            type=${manifest_data[$i+5]#*=}
            
            echo "Name:$name"
            echo "Entry:$entry"
            echo "Port:$port"
            echo "Command:$command"
            echo "Type:$type"
            echo ""
        fi
    done

    return 0
}

describe_unique(){
    NAME=$1
    CURRENT_DIR=`pwd`

    if [ -z $NAME ]; then
        default_helper 1 $NAME
        return 1
    fi

    if [ ! -f "$CURRENT_DIR/$NAME/scaffold.kubefs" ]; then
        default_helper 1 $NAME
        return 1
    fi

    eval "$(parse_scaffold "$NAME")"

    echo "Name:${scaffold_data["name"]}"
    echo "Entry:${scaffold_data["entry"]}"
    echo "Port:${scaffold_data["port"]}"
    echo "Command:${scaffold_data["command"]}"
    echo "Type:${scaffold_data["type"]}"
    echo "Docker Run:${scaffold_data["docker-run"]}"

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
        "all")  describe_all;;
        "--help") default_helper 0;;
        *) describe_unique $type;;
    esac
}

main $@
exit 0


