build:
	sudo rm -rf /usr/local/bin/scripts
	sudo cp -r scripts /usr/local/bin/scripts
	sudo cp kubefs /usr/local/bin

release-api:
	zip -r kubefs-api.zip kubefs-api -x "kubefs-api/Dockerfile" "kubefs-api/docker-compose.yaml" "kubefs-api/.dockerignore"	