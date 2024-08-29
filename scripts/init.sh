default_helper(){
    echo "
    kubefs init - initialize a new kubefs project

    Usage: kubefs init <COMMAND>
        kubefs init <name> - initialize a new kubefs project
    "
}

init_project() {
    COMMAND=$1
    if [ -z $COMMAND ]; then
        default_helper
        return 1
    fi

    source $KUBEFS_CONFIG/scripts/helper.sh

    mkdir $COMMAND && cd $COMMAND

    touch manifest.kubefs
    echo "KUBEFS_NAME=$COMMAND" >> manifest.kubefs && echo "KUBEFS_ROOT=`pwd`" >> manifest.kubefs

    print_success "Successfully created $COMMAND project!"
}

init_project $@
exit 0
