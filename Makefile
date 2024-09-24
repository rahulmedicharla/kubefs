build:
	sudo rm -rf /usr/local/bin/scripts
	sudo cp -r scripts /usr/local/bin/scripts
	sudo cp kubefs /usr/local/bin

release-api:
	zip kubefs-api.zip kubefs-api/main.go kubefs-api/go.mod kubefs-api/go.sum kubefs-api/README.md