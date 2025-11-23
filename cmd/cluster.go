/*
Copyright © 2025 Rahul Medicharla <rmedicharla@gmail.com>
*/
package cmd

import (
	"fmt"

	"github.com/rahulmedicharla/kubefs/utils"
	"github.com/spf13/cobra"
)

// clusterCmd represents the cluster command
var clusterCmd = &cobra.Command{
	Use:   "cluster [command]",
	Short: "kubefs cluster - manage clusters from provider",
	Long: `kubefs cluster - manage clusters from provider
example:
	kubefs cluster delete --flags
	kubefs cluster provision --flags
	kubefs cluster pause --flags
	kubefs cluster start --flags
	kubefs cluster main --flags
	kubefs cluster list --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		cmd.Help()
	},
}

var listClusterCmd = &cobra.Command{
	Use:   "list",
	Short: "list the availbale clusters for a target to deploy on",
	Long: `list the available clusters for a target to deploy on
example: 
	kubefs cluster list --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		fmt.Printf("Target %s \n", target)
		fmt.Printf("\t Main Cluster: %s \n", config.MainCluster)
		for i, name := range config.ClusterNames {
			fmt.Printf("\t Cluster %v: %s \n", i, name)
		}

	},
}

var mainCmd = &cobra.Command{
	Use:   "main",
	Short: "set the main cluster for a target to deploy on",
	Long: `set the main cluster for a target to deploy on
example: 
	kubefs cluster pause [clusterName] --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) < 1 {
			cmd.Help()
			return
		}

		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		// verify cloud config cluster and param matches
		clusterName := args[0]
		err = utils.VerifyClusterName(target, config, clusterName)
		if err != nil {
			utils.PrintError(err)
			return
		}

		config.MainCluster = clusterName
		err = utils.UpdateCloudConfig(&utils.ManifestData, target, config)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Cluster [%s] configured as main in %s", clusterName, target))

	},
}

var pauseCmd = &cobra.Command{
	Use:   "pause",
	Short: "pause a cluster",
	Long: `pause a cluster
example: 
	kubefs cluster pause [clusterName] --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) < 1 {
			cmd.Help()
			return
		}

		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		// verify cloud config cluster and param matches
		clusterName := args[0]
		err = utils.VerifyClusterName(target, config, clusterName)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Pausing cluster [%s] in target %s", clusterName, target))

		switch target {
		case "minikube":
			// pause cluster
			err = utils.PauseMinikubeCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		case "gcp":
			utils.PrintWarning("gcp autopilot clusters don't support pausing/stopping")
			return
		case "azure":
			err = utils.PauseAzureCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		}

		utils.PrintInfo(fmt.Sprintf("Paused cluster [%s] in target %s", clusterName, target))
	},
}

var startCmd = &cobra.Command{
	Use:   "start",
	Short: "start a cluster",
	Long: `start a cluster
example: 
	kubefs cluster start [clusterName] --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) < 1 {
			cmd.Help()
			return
		}

		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		clusterName := args[0]

		// validate cluster exists
		err = utils.VerifyClusterName(target, config, clusterName)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Starting cluster [%s] in target %s", clusterName, target))

		switch target {
		case "minikube":
			// start cluster
			err = utils.StartMinikubeCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		case "gcp":
			utils.PrintWarning("gcp autopilot clusters don't support starting clusters")
			return
		case "azure":
			err = utils.StartAzureCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		}

		utils.PrintInfo(fmt.Sprintf("Started cluster [%s] in target %s", clusterName, target))

	},
}

var deleteCmd = &cobra.Command{
	Use:   "delete",
	Short: "delete a cluster",
	Long: `delete a cluster
example: 
	kubefs cluster delete [clusterName] --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) < 1 {
			cmd.Help()
			return
		}

		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		clusterName := args[0]
		// verify cluster exists
		err = utils.VerifyClusterName(target, config, clusterName)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Deleting cluster [%s] in %s", clusterName, target))

		switch target {
		case "minikube":
			// delete cluster
			err = utils.DeleteMinikubeCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		case "gcp":
			// delete gcp cluster
			err = utils.DeleteGCPCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		case "azure":
			err = utils.DeleteAzureCluster(config, clusterName)
			if err != nil {
				utils.PrintError(err)
				return
			}
		}

		// update Manifest
		config.ClusterNames, _ = utils.RemoveClusterName(config, clusterName)
		if len(config.ClusterNames) > 0 {
			config.MainCluster = config.ClusterNames[0]
		} else {
			config.MainCluster = ""
		}

		err = utils.UpdateCloudConfig(&utils.ManifestData, target, config)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Deleted cluster [%s] in %s", clusterName, target))

	},
}

var provisionCmd = &cobra.Command{
	Use:   "provision",
	Short: "provision a cluster",
	Long: `provision a cluster
example: 
	kubefs cluster provision [clusterName] --flags
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) < 1 {
			cmd.Help()
			return
		}

		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		// Verify cloud provider target
		target, _ := cmd.Flags().GetString("target")
		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		//  Verify authentication with cloud provider
		config, err := utils.GetCloudConfigFromProvider(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		clusterName := args[0]

		// validate cluster doesn't already exist
		err = utils.VerifyClusterName(target, config, clusterName)
		if err == nil {
			utils.PrintError(fmt.Errorf("cluster %s already exists in %s", clusterName, target))
			return
		}

		utils.PrintInfo(fmt.Sprintf("Provisioning cluster [%s] in %s", clusterName, target))

		switch target {
		case "minikube":
			// provision minikube cluster
			err = utils.ProvisionMinikubeCluster(clusterName)
		case "gcp":
			// provision gcp cluster
			err = utils.ProvisionGcpCluster(config, clusterName)
		case "azure":
			// provision azure cluster
			err = utils.ProvisionAzureCluster(config, clusterName)
		}
		if err != nil {
			utils.PrintError(err)
			return
		}
		// update manifest
		config.ClusterNames = append(config.ClusterNames, clusterName)
		config.MainCluster = config.ClusterNames[0]
		err = utils.UpdateCloudConfig(&utils.ManifestData, target, config)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintInfo(fmt.Sprintf("Provisioned cluster [%s] in %s", clusterName, target))

	},
}

func init() {
	rootCmd.AddCommand(clusterCmd)

	clusterCmd.AddCommand(provisionCmd)
	clusterCmd.AddCommand(pauseCmd)
	clusterCmd.AddCommand(startCmd)
	clusterCmd.AddCommand(deleteCmd)
	clusterCmd.AddCommand(mainCmd)
	clusterCmd.AddCommand(listClusterCmd)

	clusterCmd.PersistentFlags().StringP("target", "t", "minikube", "target environment to deploy to ['minikube', 'gcp', 'azure']")

}
