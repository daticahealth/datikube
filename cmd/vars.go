package cmd

import (
	"github.com/Atrox/homedir"
	"github.com/daticahealth/datikube/auth"
	"github.com/daticahealth/datikube/logs"
)

var verboseLoggingEnabled bool
var configPath string
var coreAPIHost string

func bindFlags() {
	rootCmd.PersistentFlags().BoolVarP(&verboseLoggingEnabled, "verbose", "v", false, "print verbose messages")
	rootCmd.PersistentFlags().StringVarP(&configPath, "config", "c", "", "use a specific kubeconfig file")
	rootCmd.PersistentFlags().StringVar(&coreAPIHost, "auth-host", "https://auth.datica.com", "auth endpoint URL")
}

func expandedConfigPath() (string, error) {
	if configPath == "" {
		return "", nil
	}
	logs.Printv("Specific kubeconfig requested: " + configPath)
	return homedir.Expand(configPath)
}

func coreAuth() *auth.CoreAuth {
	return auth.New(coreAPIHost)
}
