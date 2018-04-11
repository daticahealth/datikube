package cmd

import (
	"github.com/spf13/cobra"
	"github.com/daticahealth/datikube/kubectl"
	"github.com/daticahealth/datikube/logs"
)

var whoami = &cobra.Command{
	Use:   "whoami",
	Short: "Print out information about the currently-authenticated user",
	Long: "Print out information about the currently-authenticated user. " +
		"If there is no currently-authenticated user or the stored session token is no longer " +
		"valid, the user will be prompted to sign in again.",
	Args: cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		exp, err := expandedConfigPath()
		if err != nil {
			return err
		}
		userinfo, err := kubectl.GetUserInfo(exp)
		if err != nil {
			return err
		}
		token := ""
		if userinfo != nil {
			token = userinfo.Token
		}
		user, err := getUser(token, false)
		if err != nil {
			return err
		}
		logs.Print("ID:    %s", user.ID)
		logs.Print("Email: %s", user.Email)
		return nil
	},
}
