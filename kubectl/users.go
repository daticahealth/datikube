package kubectl

import (
	"github.com/daticahealth/datikube/logs"
	"k8s.io/client-go/tools/clientcmd/api"
)

// UserName is the name that is used by default.
const UserName = "datica"

// GetUserInfo returns the configured information for the user session. Nil if it doesn't exist.
func GetUserInfo(configPath string) (*api.AuthInfo, error) {
	conf, err := GetConfig(configPath)
	if err != nil {
		return nil, err
	}
	if daticaUser, ok := conf.AuthInfos[UserName]; ok {
		return daticaUser, nil
	}
	logs.Printv("kubeconfig \"%s\" doesn't contain user: %s", configPath, UserName)
	return nil, nil
}

// PersistUser persists a session token to the datica user in the desired (or default) kubeconfig.
func PersistUser(configPath, sessionToken string) error {
	_, err := Execute(configPath, "config", "set-credentials", UserName, "--token", sessionToken)
	return err
}
