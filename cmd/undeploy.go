/*
Copyright © 2025 Rahul Medicharla <rmedicharla@gmail.com>
*/
package cmd

import (
	"fmt"
	"strings"

	"github.com/rahulmedicharla/kubefs/types"
	"github.com/rahulmedicharla/kubefs/utils"
	"github.com/spf13/cobra"
)

// undeployCmd represents the undeploy command
var undeployCmd = &cobra.Command{
	Use:   "undeploy [command]",
	Short: "kubefs undeploy - undeploy the created resources from the clusters",
	Long: `kubefs undeploy - undeploy the created resources from the clusters
example:
	kubefs undeploy all --flags,
	kubefs undeploy resource <frontend> <api> <database> --flags,
	kubefs undeploy addons <addon-name> <addon-name> --flags`,
	Run: func(cmd *cobra.Command, args []string) {
		cmd.Help()
	},
}

func undeployFromTarget(target string, commands []string) error {
	config, err := utils.GetCloudConfigFromProvider(target)
	if err != nil {
		return err
	}

	if config.MainCluster == "" {
		return fmt.Errorf("main cluster not specified. Please run 'kubefs cluster provision' to setup a main cluster")
	}

	switch target {
	case "minikube":
		// update context
		err := utils.GetMinikubeContext(config)
		if err != nil {
			return fmt.Errorf("failed to switch to local cluster context: %v", err)
		}

		// run commands
		return utils.RunMultipleCommands(commands, true, true)
	case "gcp":
		// get context
		err = utils.GetGCPClusterContext(config)
		if err != nil {
			return err
		}

		// deploy specified commands to GCP cluster
		return utils.RunMultipleCommands(commands, true, true)
	case "azure":
		err = utils.GetAzureClusterContext(config)
		if err != nil {
			return err
		}

		return utils.RunMultipleCommands(commands, true, true)
	}

	return nil
}

func undeployAddon(name string, target string) error {
	commands := []string{}
	if name == "auth" {
		commands = append(commands, "helm uninstall auth-data")
	}

	commands = append(commands, fmt.Sprintf("helm uninstall %s", name))

	err := undeployFromTarget(target, commands)
	if err != nil {
		return err
	}

	return nil
}

func undeployUnique(name string, resource *types.Resource, target string) error {
	commandBuilder := strings.Builder{}
	commandBuilder.WriteString(fmt.Sprintf("helm uninstall %s;", name))

	if resource.Type == "database" {
		commandBuilder.WriteString(fmt.Sprintf("kubectl delete namespace %s;", name))
	}

	commands := []string{
		commandBuilder.String(),
	}

	err := undeployFromTarget(target, commands)
	if err != nil {
		return err
	}

	return nil
}

var undeployAllCmd = &cobra.Command{
	Use:   "all",
	Short: "kubefs undeploy all - undeploy all the created resources from the clusters",
	Long: `kubefs undeploy all - undeploy all the created resources from the clusters
example:
	kubefs undeploy all --flags`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		target, _ := cmd.Flags().GetString("target")

		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		utils.PrintWarning(fmt.Sprintf("Undeploying all resources & addons from %s", target))

		var errors []string
		var successes []string

		for name, resource := range utils.ManifestData.Resources {
			err := undeployUnique(name, &resource, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error undeploying resource %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		for name := range utils.ManifestData.Addons {
			err := undeployAddon(name, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error undeploying addon %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error undeploying resources %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v undeployed successfully", successes))
		}
	},
}

var undeployResourceCmd = &cobra.Command{
	Use:   "resource [name, ...]",
	Short: "kubefs undeploy resource - undeploy listed resource from the clusters",
	Long: `kubefs undeploy resource - undeploy listed resource from the clusters
example:
	kubefs undeploy resource <frontend> <api> <database> --flags,
	kubefs undeploy resource <frontend> --flags
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

		target, _ := cmd.Flags().GetString("target")

		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		addons, _ := cmd.Flags().GetString("with-addons")
		var addonList []string
		if addons != "" {
			addonList = strings.Split(addons, ",")
		}

		var errors []string
		var successes []string

		utils.PrintWarning(fmt.Sprintf("Undeploying resource %v from %s", args, target))
		utils.PrintWarning(fmt.Sprintf("Including addons %v", addonList))

		for _, name := range args {
			resource, err := utils.GetResourceFromName(name)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, name)
				continue
			}

			err = undeployUnique(name, resource, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error undeploying resource %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		for _, name := range addonList {
			_, err := utils.GetAddonFromName(name)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, name)
				continue
			}

			err = undeployAddon(name, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error undeploying addon %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error undeploying resources %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v undeployed successfully", successes))
		}
	},
}

var undeployAddonCmd = &cobra.Command{
	Use:   "addons [name, ...]",
	Short: "kubefs undeploy addon - undeploy listed addons from the clusters",
	Long: `kubefs undeploy addon - undeploy listed addons from the clusters
example:
	kubefs undeploy addon <addon-name> <addon-name> --flags,
	kubefs undeploy addon <addon-name> --flags
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

		target, _ := cmd.Flags().GetString("target")

		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		var errors []string
		var successes []string

		utils.PrintWarning(fmt.Sprintf("Undeploying addons %v from %s", args, target))

		for _, name := range args {
			_, err := utils.GetAddonFromName(name)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, name)
				continue
			}

			err = undeployAddon(name, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error undeploying addon %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error undeploying resources %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v undeployed successfully", successes))
		}
	},
}

func init() {
	rootCmd.AddCommand(undeployCmd)
	undeployCmd.AddCommand(undeployAllCmd)
	undeployCmd.AddCommand(undeployResourceCmd)
	undeployCmd.AddCommand(undeployAddonCmd)

	undeployCmd.PersistentFlags().StringP("target", "t", "minikube", "target cluster to undeploy the resources from ['minikube', 'gcp']")

	undeployCmd.PersistentFlags().BoolP("pause", "p", false, "Pause the cluster after undeploying the resources")

	undeployResourceCmd.Flags().StringP("with-addons", "a", "", "include addons in the undeploy")
}
