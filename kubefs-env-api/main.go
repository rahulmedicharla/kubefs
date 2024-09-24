package main

import (
    "fmt"
    "net/http"
    "github.com/gorilla/mux"
    "os"
    "encoding/json"
    "io/ioutil"
    "bytes"
    "github.com/joho/godotenv"
)

type ApiRequest struct {
    Method string `json:"method"`
    Url string `json:"url"`
    Port string `json:"port"`
    Headers map[string]string `json:"headers"`
    Path string `json:"path"`
    Body string `json:"body"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    response := map[string]string{"status": "ok"}
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func getEnvHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    key := vars["key"]
    value := os.Getenv(key)
    if value == "" {
        response := map[string]string{"key": key, "value": "NotFound"}
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(response)
        return
    }
    response := map[string]string{"key": key, "value": value}
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func apiHandler(w http.ResponseWriter, r *http.Request) {

    body, err := ioutil.ReadAll(r.Body)
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }
    defer r.Body.Close()

    var forward ApiRequest
    err = json.Unmarshal(body, &forward)
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }

    client := &http.Client{}
    url := fmt.Sprintf("%s:%s%s", forward.Url, forward.Port, forward.Path)
    req, err := http.NewRequest(forward.Method, url, bytes.NewBuffer([]byte(forward.Body)))
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }

    for key, value := range forward.Headers {
        req.Header.Set(key, value)
    }

    resp, err := client.Do(req)
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }

    defer resp.Body.Close()

    body, err = ioutil.ReadAll(resp.Body)
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }
    
    w.Header().Set("Content-Type", "application/json")
    w.Write(body)
}

func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        origin := r.Header.Get("Origin")
        if origin == "" {
            origin = "*"
        }
        w.Header().Set("Access-Control-Allow-Origin", origin)
        w.Header().Set("Access-Control-Allow-Methods", "GET")
        w.Header().Set("Access-Control-Allow-Headers", "*")
        if r.Method == "OPTIONS" {
            w.WriteHeader(http.StatusOK)
            return
        }
        next.ServeHTTP(w, r)
    })
}

func main() {
    err := godotenv.Load()
    if err != nil {
        fmt.Println("Error loading .env file")
    }
    // Create a new router
    r := mux.NewRouter()

    r.Use(corsMiddleware)

    // Define the routes
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/env/{key}", getEnvHandler).Methods("GET")
    r.HandleFunc("/api", apiHandler).Methods("POST")

    // Start the server
    fmt.Println("Server is running on port 5000")
    http.ListenAndServe(":5000", r)
}
