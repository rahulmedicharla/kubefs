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
    "encoding/base64"
    "time"
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
    fmt.Println(fmt.Sprintf("envHandler: %s", time.Now().Format("2006-01-02 15:04:05")))
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
    fmt.Println(fmt.Sprintf("apiHandler: %s", time.Now().Format("2006-01-02 15:04:05")))
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
    url := fmt.Sprintf("%s:%s/auth%s", forward.Url, forward.Port, forward.Path)
    
    fmt.Println(fmt.Sprintf("apiHandler: request to %s :  %s", url, time.Now().Format("2006-01-02 15:04:05")))
    
    req, err := http.NewRequest(forward.Method, url, bytes.NewBuffer([]byte(forward.Body)))
    if err != nil {
        fmt.Println(err)
        http.Error(w, fmt.Sprintf("{\"error\": \"%s\"}", err.Error()), http.StatusBadRequest)
        return
    }

    for key, value := range forward.Headers {
        req.Header.Set(key, value)
    }

    CLIENT_ID := os.Getenv("CLIENT_ID")
    CLIENT_SECRET := os.Getenv("CLIENT_SECRET")

    if CLIENT_ID == "" || CLIENT_SECRET == "" {
        http.Error(w, "Unvalid client credentials", http.StatusUnauthorized)
        return
    }
    
    encodedClientID := base64.StdEncoding.EncodeToString([]byte(CLIENT_ID))
    encodedClientSecret := base64.StdEncoding.EncodeToString([]byte(CLIENT_SECRET))

    req.Header.Set("X-CLIENT-ID", encodedClientID)
    req.Header.Set("X-CLIENT-SECRET", encodedClientSecret)

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
