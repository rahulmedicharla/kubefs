/*
Copyright © 2025 Rahul Medicharla <rmedicharla@gmail.com>
*/
package cmd

import (
	"context"
	"fmt"
	"strings"

	"github.com/rahulmedicharla/kubefs/types"
	"github.com/rahulmedicharla/kubefs/utils"
	"github.com/spf13/cobra"
	"github.com/zalando/go-keyring"
)

// configCmd represents the config command
var configCmd = &cobra.Command{
	Use:   "config [command]",
	Short: "kubefs config - configure kubefs environment and auth configurations",
	Long: `kubefs config - configure kubefs environment and auth configurations
example: 
	kubefs config docker --flag
	`,
	Run: func(cmd *cobra.Command, args []string) {
		cmd.Help()
	},
}

var gcpCmd = &cobra.Command{
	Use:   "gcp",
	Short: "Configure GCP settings",
	Long: `Configure GCP settings for kubefs
example: 
	kubefs config gcp --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		remove, err := cmd.Flags().GetBool("remove")
		if err != nil {
			utils.PrintError(fmt.Errorf("error reading remove flag: %v", err))
			return
		}

		if remove {
			// Revoke gcloud authentication
			err = utils.RunCommand("gcloud auth revoke", true, true)
			if err != nil {
				utils.PrintError(fmt.Errorf("error revoking GCP authentication: %v", err))
				return
			}

			err = utils.RemoveCloudConfig(&utils.ManifestData, "gcp")
			if err != nil {
				utils.PrintError(fmt.Errorf("error removing GCP configuration from manifest: %v", err))
				return
			}

			utils.PrintInfo("GCP authentication revoked successfully")
		} else {

			// Authenticate and enable with GCP using gcloud CLI
			err = utils.AuthenticateGCP()
			if err != nil {
				utils.PrintError(fmt.Errorf("error authenticating with GCP: %v", err))
				return
			}

			// gather configuration details
			var projectName string
			ctx := context.Background()

			err = utils.ReadInput("Enter GCP Project Id: ", &projectName)
			if err != nil {
				utils.PrintError(fmt.Errorf("error reading GCP Project Id: %v", err))
				return
			}

			// Setup GCP
			projectId, region, err := utils.SetupGcp(ctx, projectName)
			if err != nil {
				utils.PrintError(err)
				return
			}

			// Save GCP configuration
			cloudConfig := types.CloudConfig{
				ProjectId:    *projectId,
				ProjectName:  projectName,
				Region:       *region,
				ClusterNames: make([]string, 0),
			}

			// Add new config
			err = utils.UpdateCloudConfig(&utils.ManifestData, "gcp", &cloudConfig)
			if err != nil {
				utils.PrintError(fmt.Errorf("error saving GCP configuration to manifest: %v", err))
				return
			}

			utils.PrintInfo(fmt.Sprintf("GCP Project configured successfully: %s", projectName))

		}
	},
}

var azureCmd = &cobra.Command{
	Use:   "azure",
	Short: "Configure Azure settings",
	Long: `Configure Azure settings for kubefs
example: 
	kubefs config azure --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		remove, err := cmd.Flags().GetBool("remove")
		if err != nil {
			utils.PrintError(fmt.Errorf("error reading remove flag: %v", err))
			return
		}

		if remove {
			// Revoke az authentication
			err = utils.RunCommand("az logout", true, true)
			if err != nil {
				utils.PrintError(fmt.Errorf("error revoking Azure authentication: %v", err))
				return
			}

			err = utils.RemoveCloudConfig(&utils.ManifestData, "azure")
			if err != nil {
				utils.PrintError(fmt.Errorf("error removing Azure configuration from manifest: %v", err))
				return
			}

			utils.PrintInfo("Azure authentication revoked successfully")
		} else {

			// Authenticate and enable with Azure using az CLI
			err = utils.AuthenticateAzure()
			if err != nil {
				utils.PrintError(fmt.Errorf("error authenticating with Azure: %v", err))
				return
			}

			// gather configuration details
			var subscription string
			ctx := context.Background()

			err = utils.ReadInput("Enter Azure Subscription Id: ", &subscription)
			if err != nil {
				utils.PrintError(fmt.Errorf("error reading Azure Subscription Id: %v", err))
				return
			}

			// Setup GCP
			resourceGroup, region, err := utils.SetupAzure(ctx, subscription)
			if err != nil {
				utils.PrintError(err)
				return
			}

			// Save GCP configuration
			cloudConfig := types.CloudConfig{
				SubscriptionId: subscription,
				ResourceGroup:  *resourceGroup,
				Region:         *region,
				ClusterNames:   make([]string, 0),
			}

			// Add new config
			err = utils.UpdateCloudConfig(&utils.ManifestData, "azure", &cloudConfig)
			if err != nil {
				utils.PrintError(fmt.Errorf("error saving Azure configuration to manifest: %v", err))
				return
			}

			utils.PrintInfo("Azure Project configured successfully")

		}
	},
}

var dockerCmd = &cobra.Command{
	Use:   "docker",
	Short: "Configure Docker settings",
	Long: `Configure Docker settings for kubefs
example: 
	kubefs config docker --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// get service information
		service := "docker"
		user := "kubefs"

		// Read remove flag
		remove, err := cmd.Flags().GetBool("remove")
		if err != nil {
			utils.PrintError(fmt.Errorf("error reading remove flag: %v", err))
			return
		}

		if remove {
			err := keyring.Delete(service, user)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deleting Docker credentials: %v", err))
				return
			}
			utils.PrintInfo("Docker credentials removed successfully")
		} else {
			var username, pat string
			err := utils.ReadInput("Enter Docker username: ", &username)
			if err != nil {
				utils.PrintError(fmt.Errorf("error reading Docker username: %v", err))
			}

			err = utils.ReadInput("Enter Docker PAT (https://docs.docker.com/security/for-developers/access-tokens/): ", &pat)
			if err != nil {
				utils.PrintError(fmt.Errorf("error reading Docker PAT: %v", err))
			}

			err = keyring.Set(service, user, fmt.Sprintf("%s:%s", username, pat))
			if err != nil {
				utils.PrintError(fmt.Errorf("error saving Docker credentials: %v", err))
				return
			}

			utils.PrintInfo("Saving Docker credentials")
		}
	},
}

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all configurations",
	Long: `List all configurations for kubefs
example: 
	kubefs config list
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		user := "kubefs"
		services := []string{"docker"}

		fmt.Println("Listing all configurations")

		for _, service := range services {
			creds, err := keyring.Get(service, user)
			if err != nil {
				fmt.Printf("Error getting %s credentials | No credentials set: %v\n", service, err)
			} else {
				username, password := strings.Split(creds, ":")[0], strings.Split(creds, ":")[1]
				fmt.Printf("%s credentials:\n", service)
				fmt.Println("Username:", username)
				fmt.Println("Password/PAT:", password)
			}

			fmt.Println()
		}

		fmt.Println("Cloud Configurations:")
		for provider, config := range utils.ManifestData.CloudConfig {
			fmt.Printf("Provider: %s\n", provider)
			fmt.Printf("Project ID: %s\n", config.ProjectId)
			for _, clusterName := range config.ClusterNames {
				fmt.Printf("Cluster %s", clusterName)
			}
			fmt.Println()
		}
	},
}

func init() {
	rootCmd.AddCommand(configCmd)

	configCmd.AddCommand(listCmd)
	configCmd.AddCommand(dockerCmd)
	configCmd.AddCommand(gcpCmd)
	configCmd.AddCommand(azureCmd)

	configCmd.PersistentFlags().BoolP("remove", "r", false, "remove the associated configuration")
}
