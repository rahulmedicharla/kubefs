default_helper(){
    if [ $1 -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs init - initialize a new kubefs project

    kubefs init <name> - initialize a new kubefs project"
}

init_project() {
    if [ -z $1 ]; then
        default_helper 0
        return 1
    fi

    mkdir $1 && cd $1

    touch manifest.kubefs
    echo "KUBEFS_NAME=$1" >> manifest.kubefs && echo "KUBEFS_ROOT=`pwd`" >> manifest.kubefs

    echo "Successfully created $1 project"
}

init_project $@
exit 0
