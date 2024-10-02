# Welcome to kubefs
## kubefs is a cli desgined to automate the creation, testing, and deployment of production-ready fullstack applications onto kubernetes cluster.

### Installation

copy the repo down, and run ```make build```

this will add the kubefs cli to your usr/local/bin which should automatically make it available on the path

then run ```kubefs setup``` to download any required dependencies that don't exist & set up project

### Usage

Once installed the CLI is designed to be very simple to use.

To start, run ```kubefs init <name> ``` to create a new project. This project will be base scope for the resources you want to create within the project.

Afterwards, you can then create the resources you want using ```kubefs create <resource_type> <name> -f <framework> -p <port>```

Currently, we offer three types of resources, frontend, api, and database. Each resource has different frameworks you can use to your liking and port specifications. 

If you would like to use environment variables with your resource, you can define a .env file and consume it naturally. If you would like kubefs to handle the environment variable to be a kubernetes native secret, create a env.kubefs file and populate them following the standard .env key-value format. In local development, these will be handled as normal environment variables, however, in the helm charts for the kubernetes deployment they will be treated as kubernetes secrets and consumed as such.
