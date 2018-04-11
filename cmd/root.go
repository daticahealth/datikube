package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/daticahealth/datikube/logs"
)

var rootCmd = &cobra.Command{
	Use:   "datikube",
	Short: "Datica's CLI for interacting with Kubernetes deployments.",
	Long:  "Datica's CLI for interacting with Kubernetes deployments.",
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		logs.ConfigureVerbosity(verboseLoggingEnabled)
	},
}

// Execute invokes the command and exits in the event of an error.
func Execute() {
	bindFlags()
	bindSubcommands()
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
