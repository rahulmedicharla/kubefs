default_helper(){
    TYPE=$1
    if [ $TYPE -eq 1 ]; then
        echo "${2} is not a valid argument, please follow types below"
    fi

    echo "
    kubefs init <name> - initialize a new kubefs project
    "
}

init_project() {
    if [ -z $1 ]; then
        default_helper 1 $2
        return 1;
    fi

    mkdir $1 && cd $1

    # create project directory && configuration files
    touch manifest.kubefs
    echo "KUBEFS_NAME=$1" >> manifest.kubefs && echo "KUBEFS_ROOT=`pwd`" >> manifest.kubefs

    echo "Successfully created $1 project"
}

init_project $1
exit 0
