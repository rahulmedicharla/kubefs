validate_project(){      
    if [ ! -f "`pwd`/manifest.kubefs" ]; then
        echo "You are not in a valid project folder, please initialize project using kubefs init or look at kubefs --help for more information"
        return 1
    fi
}