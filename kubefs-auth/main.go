package main

import (
    "fmt"
    "net/http"
    "github.com/gorilla/mux"
    "os"
    "encoding/json"
    "github.com/joho/godotenv"
    "encoding/base64"
    "time"
)
func healthHandler(w http.ResponseWriter, r *http.Request) {
    response := map[string]string{"status": "ok"}
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func authHandler(w http.ResponseWriter, r *http.Request) {
    fmt.Println(fmt.Sprintf("Authorizing... %s", time.Now().Format("2006-01-02 15:04:05")))

    client_id, err := base64.StdEncoding.DecodeString(r.Header.Get("X-CLIENT-ID"))
    if err != nil {
        fmt.Println("Error decoding client_id %s", err)
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    client_secret, err := base64.StdEncoding.DecodeString(r.Header.Get("X-CLIENT-SECRET"))
    if err != nil {
        fmt.Println("Error decoding client_secret %s", err)
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    if string(client_id) == "" || string(client_secret) == "" {
        fmt.Println("Client_id or client_secret is empty")
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    env := os.Getenv(string(client_id))
    if env == "" || env != string(client_secret) {
        fmt.Println("Client_id or client_secret is invalid")
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    fmt.Println("Authorized... %s", time.Now().Format("2006-01-02 15:04:05"))

    w.WriteHeader(http.StatusOK)

}
func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
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
        fmt.Println("No .env file found")
    }
    // Create a new router
    r := mux.NewRouter()

    r.Use(corsMiddleware)

    // Define the routes
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/auth", authHandler).Methods("GET")

    // Start the server
    fmt.Println("Server is running on port 6000")
    http.ListenAndServe(":6000", r) 
}
