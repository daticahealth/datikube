package cmd

import (
	"github.com/Atrox/homedir"
	"github.com/spf13/cobra"
	"github.com/daticahealth/datikube/kubectl"
	"github.com/daticahealth/datikube/logs"
)

var setContext = func() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "set-context <name> <cluster-url> <ca-file>",
		Short: "Add or update cluster context in local kubeconfig",
		Long: "Add or update cluster context in local kubeconfig. This command will prompt for " +
			"valid Datica account credentials, then set user, cluster, and context entries " +
			"appropriately. " + `

<name> is the name you'd like to use for this cluster, like "prod" or "staging".

<cluster-url> is a URL at which this cluster's kube-apiserver is accessible.

<ca-file> is a relative path to the CA cert for this cluster.

For example, using a local minikube setup:

	datikube set-context my-minikube https://192.168.99.100:8443 ~/.minikube/ca.crt
`,
		Args: cobra.ExactArgs(3),
		RunE: func(cmd *cobra.Command, args []string) error {
			name, clusterURL, caPath := args[0], args[1], args[2]
			expCAPath, err := homedir.Expand(caPath)
			if err != nil {
				return err
			}
			addSkipVerify, err := cmd.Flags().GetBool("insecure-skip-tls-verify")
			if err != nil {
				return err
			}

			exp, err := expandedConfigPath()
			if err != nil {
				return err
			}
			authInfo, err := kubectl.GetUserInfo(exp)
			if err != nil {
				return err
			}
			sessionToken := ""
			if authInfo != nil {
				sessionToken = authInfo.Token
			}
			user, err := getUser(sessionToken, false)
			if err != nil {
				return err
			}
			err = kubectl.PersistUser(exp, user.SessionToken)
			if err != nil {
				return err
			}

			kargs := []string{"config", "set-cluster", name, "--server", clusterURL, "--certificate-authority", expCAPath}
			if addSkipVerify {
				kargs = append(kargs, "--insecure-skip-tls-verify", "true")
			}
			_, err = kubectl.Execute(exp, kargs...)
			if err != nil {
				return err
			}

			_, err = kubectl.Execute(exp, "config", "set-context", name, "--cluster", name, "--user", kubectl.UserName)
			if err != nil {
				return err
			}

			logs.Print("Context set. Use \"--context=%s\" in your kubectl commands for this cluster. Example:", name)
			logs.Print("")
			logs.Print("\tkubectl --context=%s get pods", name)

			return nil
		},
	}

	cmd.Flags().Bool("insecure-skip-tls-verify", false, "Add the --insecure-skip-tls-verify option to the cluster")

	return cmd
}()
