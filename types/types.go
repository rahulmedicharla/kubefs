package types

import "v8.run/go/exp/util/maps"

type Project struct {
	KubefsName  string                 `yaml:"name"`
	Version     string                 `yaml:"version"`
	Description string                 `yaml:"description"`
	Resources   map[string]Resource    `yaml:"resources"`
	Addons      map[string]Addon       `yaml:"addons"`
	CloudConfig map[string]CloudConfig `yaml:"cloud_config"`
}

type Resource struct {
	Port            int               `yaml:"port"`
	Type            string            `yaml:"type"`
	Framework       string            `yaml:"framework"`
	AttachCommand   map[string]string `yaml:"attach_command"`
	UpLocal         string            `yaml:"up_local,omitempty"`
	LocalHost       string            `yaml:"local_host,omitempty"`
	DockerHost      string            `yaml:"docker_host,omitempty"`
	DockerRepo      string            `yaml:"docker_repo,omitempty"`
	ClusterHost     string            `yaml:"cluster_host,omitempty"`
	ClusterHostRead string            `yaml:"cluster_host_read,omitempty"`
	Dependents      []string          `yaml:"dependents,omitempty"`
	Opts            map[string]string `yaml:"opts,omitempty"`
	Environment     map[string]string `yaml:"environment,omitempty"`
}

type Addon struct {
	Port         int               `yaml:"port"`
	DockerRepo   string            `yaml:"docker_repo"`
	LocalHost    string            `yaml:"local_host"`
	DockerHost   string            `yaml:"docker_host"`
	ClusterHost  string            `yaml:"cluster_host"`
	Dependencies []string          `yaml:"dependencies,omitempty"`
	Environment  map[string]string `yaml:"environment,omitempty"`
}

type CloudConfig struct {
	ProjectId      string   `yaml:"project_id,omitempty"`
	ProjectName    string   `yaml:"project_name,omitempty"`
	Region         string   `yaml:"region,omitempty"`
	ClusterNames   []string `yaml:"cluster_names,omitempty"`
	MainCluster    string   `yaml:"main_cluster,omitempty"`
	SubscriptionId string   `yaml:"subscription_id,omitempty"`
	ResourceGroup  string   `yaml:"resource_group,omitempty"`
}

type ApiResponse struct {
	Token  string `json:"token,omitempty"`
	Detail string `json:"detail,omitempty"`
}

const (
	DOCKER_LOGIN_ENDPOINT = "https://hub.docker.com/v2/users/login/"
	DOCKER_REPO_ENDPOINT  = "https://hub.docker.com/v2/repositories/"
)

const (
	N      = 32768
	R      = 8
	P      = 1
	KeyLen = 32
)

var FRAMEWORKS = map[string]maps.Set[string]{
	"api":      maps.NewSet("nest", "fast", "gin"),
	"frontend": maps.NewSet("next", "sveltekit", "remix"),
	"database": maps.NewSet("postgresql", "redis"),
	"addons":   maps.NewSet("auth", "gateway"),
}

var TARGETS = maps.NewSet("minikube", "gcp", "azure")
