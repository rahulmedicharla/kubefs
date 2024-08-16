init_project() {
    if [ -z $1 ]; then
        default_helper $2
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
