# Welcome to the kubefs-api

## This api is meant to be used as a backend service for frontend applications served in kubernetes

### This api has two main purposes:

1. It allows frontend applications to access dynamic environment variables instead of at build time

/env/{key} will return the value of the environment variable for the given key 

2. It allows frontend applications to access api endpoints from kubernetes

/api will forward the request to the given api endpoint, just add the content for the request url, port, headers and body and it will forward the request to the api

- example:

curl -X POST http://localhost:5000/api \
    -H "Content-Type: application/json" \
-d '{
        "Method": "GET",
        "Url": "http://localhost",
        "Port": "8080",
        "Headers": {
        "Content-Type": "application/json"
        },
        "Path": "/todos",
        "Body": ""
    }'

This will forward a get request to http://localhost:8080/todos with the headers {"Content-Type": "application/json"}