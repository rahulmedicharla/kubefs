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
    Api string `json:"api"`
    Headers map[string]string `json:"headers"`
    Path string `json:"path"`
    Body string `json:"body"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    response := map[string]string{"status": "ok"}
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func envHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    key := vars["key"]
    value := os.Getenv(key)

    if value == "" {
        http.Error(w, fmt.Sprintf("{\"error\": \"Key %s not found\"}", key), http.StatusBadRequest)
        return
    }

    response := map[string]string{key: value}
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

    api_host := os.Getenv(fmt.Sprintf("%s_HOST", forward.Api))
    api_port := os.Getenv(fmt.Sprintf("%s_PORT", forward.Api))
    
    if api_port == "" || api_host == "" {
        fmt.Println(fmt.Sprintf("{\"apiHandler\": \"Invalid api %s\"}", forward.Api))
        http.Error(w, "Invalid port", http.StatusBadRequest)
        return
    }
    
    client := &http.Client{}
    url := fmt.Sprintf("http://%s:%s/auth%s", api_host, api_port, forward.Path)
    
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
        http.Error(w, "Invalid client credentials", http.StatusUnauthorized)
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

    fmt.Println(fmt.Sprintf("apiHandler: response from %s :  %s", url, time.Now().Format("2006-01-02 15:04:05")))
    
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
    r.HandleFunc("/api", apiHandler).Methods("POST")
    r.HandleFunc("/env/{key}", envHandler).Methods("GET")

    // Start the server
    fmt.Println("Server is running on port 5000")
    http.ListenAndServe(":5000", r)
}
