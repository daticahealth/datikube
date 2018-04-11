package kubectl

import (
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
)

// GetConfig parses and returns a kubeconfig file.
func GetConfig(configPath string) (*api.Config, error) {
	args := []string{"config", "view", "--merge=true", "-o", "yaml"}
	stdout, err := Execute(configPath, args...)
	if err != nil {
		return nil, err
	}
	return clientcmd.Load(stdout)
}
