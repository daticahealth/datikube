package cmd

import (
	"github.com/spf13/cobra"
	"github.com/daticahealth/datikube/kubectl"
)

var refresh = func() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "refresh",
		Short: "Acquire a new session token and persist it to local kubeconfig",
		Long: "Acquire a new session token and persist it to local kubeconfig. By default, any " +
			"existing token will not be checked, and the datica user in the local kubeconfig will " +
			"be overwritten if it exists.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
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
			reuseSession, err := cmd.Flags().GetBool("reuse-session")
			if err != nil {
				return err
			}
			user, err := getUser(sessionToken, !reuseSession)
			if err != nil {
				return err
			}
			return kubectl.PersistUser(exp, user.SessionToken)
		},
	}

	cmd.Flags().Bool("reuse-session", false, "Do not overwrite token if it is still valid")

	return cmd
}()
