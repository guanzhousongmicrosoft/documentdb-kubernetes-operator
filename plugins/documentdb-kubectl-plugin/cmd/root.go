package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	pluginVersion = "dev"
	rootCmd       = &cobra.Command{
		Use:          "documentdb",
		Short:        "kubectl plugin for Azure Cosmos DB for MongoDB (DocumentDB)",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}
)

func Execute(version string) {
	pluginVersion = version
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.AddCommand(newPromoteCommand())
	rootCmd.AddCommand(newStatusCommand())
	rootCmd.AddCommand(newEventsCommand())
	rootCmd.AddCommand(newVersionCommand())
}

func newVersionCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the version of kubectl-documentdb",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("kubectl-documentdb version %s\n", pluginVersion)
		},
	}
}
