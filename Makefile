build:
	sudo rm -rf /usr/local/bin/scripts
	sudo cp -r scripts /usr/local/bin/scripts
	sudo cp kubefs /usr/local/bin

reset:
	(cd .. && rm -rf tester && kubefs init tester && kubefs create api test1)