package cmd

func bindSubcommands() {
	rootCmd.AddCommand(setContext)
	rootCmd.AddCommand(refresh)
	rootCmd.AddCommand(whoami)
}
