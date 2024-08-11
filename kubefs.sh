#!/bin/bash

function default_helper {
    echo "${1} is not a valid argument, please follow types below
    kubefs - a cli tool to create & deploy full stack applications onto kubernetes clusters

    kubefs build - create docker images & helm charts for created resources to be deployed onto the clusters
    kubefs config - config login credentials & deployment targets to be used 
    kubefs create - easily create backend, frontend, & db constructs to be used within your application
    kubefs deploy - deploy the build targets onto the cluster!
    "
}

case $1 in 
    "create") source scripts/create.sh;;
    "build") source scripts/build.sh;;
    "deploy") source scripts/deploy.sh;;
    "config") source scripts/config.sh;;
    "--help") default_helper;;
    *) default_helper ;;
esac

exit 0


