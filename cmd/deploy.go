/*
Copyright © 2025 Rahul Medicharla <rmedicharla@gmail.com>
*/
package cmd

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/rahulmedicharla/kubefs/types"
	"github.com/rahulmedicharla/kubefs/utils"
	"github.com/spf13/cobra"
	"github.com/thanhpk/randstr"
	"golang.org/x/crypto/scrypt"
)

// deployCmd represents the deploy command
var deployCmd = &cobra.Command{
	Use:   "deploy [command]",
	Short: "kubefs deploy - create helm charts & deploy the build targets onto the cluster",
	Long: `kubefs deploy - create helm charts & deploy the build targets onto the cluster
example:
	kubefs deploy all --flags,
	kubefs deploy resource <frontend> <api> <database> --flags,
	kubefs deploy addons <addon-name> <addon-name> --flags,`,
	Run: func(cmd *cobra.Command, args []string) {
		cmd.Help()
	},
}

func deployToTarget(target string, commands []string) error {
	// verify cloud config
	config, err := utils.GetCloudConfigFromProvider(target)
	if err != nil {
		return err
	}

	if config.MainCluster == "" {
		return fmt.Errorf("main cluster not specified. Please run 'kubefs cluster provision' to setup a main cluster")
	}

	switch target {
	case "minikube":
		err := utils.GetMinikubeContext(config)
		if err != nil {
			return err
		}

		return utils.RunMultipleCommands(commands, true, true)
	case "gcp":
		err = utils.GetGCPClusterContext(config)
		if err != nil {
			return err
		}

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

func deployAddon(name string, addon *types.Addon, onlyHelmify bool, onlyDeploy bool, target string) error {
	err := utils.RunCommand(fmt.Sprintf("docker pull %s", addon.DockerRepo), true, true)
	if err != nil {
		return err
	}

	if !onlyDeploy {
		// helmify
		commands := []string{
			fmt.Sprintf("(cd addons/%s; rm -rf deploy; helm pull oci://registry-1.docker.io/rmedicharla/deploy --untar)", name),
		}
		switch name {
		case "auth":
			commands = append(commands,
				fmt.Sprintf("(cd addons/%s; rm -rf postgresql; helm pull oci://registry-1.docker.io/bitnamicharts/postgresql --untar)", name),
				fmt.Sprintf("(cd addons/%s/postgresql/templates && echo '' > NOTES.txt)", name),
			)
		case "gateway":
		}

		err = utils.RunMultipleCommands(commands, true, true)
		if err != nil {
			return err
		}
	}
	if !onlyHelmify {
		// deploy
		commandBuilder := strings.Builder{}
		baseConfigs := []string{
			"--set image.repository=" + addon.DockerRepo,
			"--set service.port=" + fmt.Sprintf("%v", addon.Port),
			"--set namespace=" + name,
			"--set readinessProbe.httpGet.path=/health",
			"--set livenessProbe.httpGet.path=/health",
			"--set service.type=ClusterIP",
			"--set ingress.enabled=false",
		}

		switch name {
		case "auth":
			pass := randstr.String(16)
			configs := []string{
				"--set namespaceOverride=auth",
				"--set auth.postgresPassword=" + pass,
				"--set architecture=replication",
				"--set auth.database=auth",
				"--set readReplicas.replicaCount=3",
				"--set primary.persistence.size=1Gi",
				"--set readReplicas.persistence.size=1Gi",
				"--set primary.initdb.scripts.\"init-user\\.sql\"=\"CREATE TABLE IF NOT EXISTS accounts (uid UUID PRIMARY KEY\\, email TEXT\\, password TEXT);\"",
			}

			var allowedOrigins []string
			for _, n := range addon.Dependencies {
				attachedResource, err := utils.GetResourceFromName(n)
				if err != nil {
					return err
				}

				allowedOrigins = append(allowedOrigins, attachedResource.ClusterHost)
			}
			authConfigs := []string{
				"--set env[0].name=ALLOWED_ORIGINS",
				"--set env[0].value=" + fmt.Sprintf("'%s'", strings.Join(allowedOrigins, "&")),
				"--set env[1].name=PORT",
				"--set env[1].value=" + fmt.Sprintf("%v", addon.Port),
				"--set env[2].name=WRITE_CONNECTION_STRING",
				"--set env[2].value=" + fmt.Sprintf("postgresql://postgres:%s@auth-data-postgresql-primary:5432/auth?sslmode=disable", pass),
				"--set env[3].name=READ_CONNECTION_STRING",
				"--set env[3].value=" + fmt.Sprintf("postgresql://postgres:%s@auth-data-postgresql-read:5432/auth?sslmode=disable", pass),
			}

			count := 4
			for key, value := range addon.Environment {
				authConfigs = append(authConfigs, fmt.Sprintf("--set env[%v].name=%s --set env[%v].value=%s", count, key, count, value))
				count++
			}

			commandBuilder.WriteString("helm upgrade --install auth addons/auth/deploy")
			authConfigs = append(authConfigs, baseConfigs...)
			for _, c := range authConfigs {
				commandBuilder.WriteString(fmt.Sprintf(" %s", c))
			}
			commandBuilder.WriteString(";")

			commandBuilder.WriteString("helm upgrade --install auth-data addons/auth/postgresql")
			for _, c := range configs {
				commandBuilder.WriteString(fmt.Sprintf(" %s", c))
			}

		case "gateway":
			var allowedOrigins []string
			var clients []string
			for _, n := range addon.Dependencies {
				attachedResource, err := utils.GetResourceFromName(n)
				if err != nil {
					return err
				}

				secret, err := base64.URLEncoding.DecodeString(attachedResource.Environment["clientSecret"])
				if err != nil {
					return err
				}

				// encrypt with scrypt
				salt := make([]byte, 8)
				rand.Read(salt)
				key, err := scrypt.Key(secret, salt, types.N, types.R, types.P, types.KeyLen)
				if err != nil {
					return err
				}

				b64Salt := base64.StdEncoding.EncodeToString(salt)
				b64Key := base64.StdEncoding.EncodeToString(key)

				encodedKey := fmt.Sprintf("%d?%d?%d?%d?%s?%s", types.N, types.R, types.P, types.KeyLen, b64Salt, b64Key)

				clients = append(clients, fmt.Sprintf("%s:%s", attachedResource.Environment["clientId"], encodedKey))
				allowedOrigins = append(allowedOrigins, attachedResource.DockerHost)
			}

			gatewayConfigs := []string{
				// env variables
				"--set env[0].name=ALLOWED_ORIGINS",
				"--set env[0].value=" + fmt.Sprintf("'%s'", strings.Join(allowedOrigins, "&")),
				"--set env[1].name=PORT",
				"--set env[1].value=" + fmt.Sprintf("%v", addon.Port),
				// secret 0
				"--set secrets[0].name=public_key.pem",
				"--set secrets[0].value=files/public_key.pem",
				"--set secrets[0].secretRef=gateway-deploy-secret",
				"--set secrets[0].valueIsFile=true",
				// secret 1
				"--set secrets[1].name=private_key.pem",
				"--set secrets[1].value=files/private_key.pem",
				"--set secrets[1].secretRef=gateway-deploy-secret",
				"--set secrets[1].valueIsFile=true",
				// secret 2
				"--set secrets[2].name=CLIENTS",
				"--set secrets[2].value=" + fmt.Sprintf("'%s'", strings.Join(clients, "&")),
				"--set secrets[2].secretRef=gateway-deploy-secret",
				"--set secrets[2].valueIsFile=false",
				// volumes
				"--set volumes[0].name=keys",
				"--set volumes[0].secret.secretName=gateway-deploy-secret",
				// volume mounts
				"--set volumeMounts[0].name=keys",
				"--set volumeMounts[0].mountPath=/etc/ssl/private/private_key.pem",
				"--set volumeMounts[0].subPath=private_key.pem",
				"--set volumeMounts[1].name=keys",
				"--set volumeMounts[1].mountPath=/etc/ssl/public/public_key.pem",
				"--set volumeMounts[1].subPath=public_key.pem",
			}

			err = utils.RunCommand("mkdir -p addons/gateway/deploy/files && cp addons/gateway/public_key.pem addons/gateway/deploy/files && cp addons/gateway/private_key.pem addons/gateway/deploy/files", true, true)
			if err != nil {
				return err
			}

			count := 2
			for key, value := range addon.Environment {
				gatewayConfigs = append(gatewayConfigs, fmt.Sprintf("--set env[%v].name=%s --set env[%v].value=%s", count, key, count, value))
				count++
			}

			commandBuilder.WriteString("helm upgrade --install gateway addons/gateway/deploy")
			gatewayConfigs = append(gatewayConfigs, baseConfigs...)
			for _, c := range gatewayConfigs {
				commandBuilder.WriteString(fmt.Sprintf(" %s", c))
			}
		}

		commands := []string{
			commandBuilder.String(),
		}

		err = deployToTarget(target, commands)
		if err != nil {
			return err
		}
	}

	return nil
}

func deployUnique(name string, resource *types.Resource, onlyHelmify bool, onlyDeploy bool, target string) error {
	err := utils.RunCommand(fmt.Sprintf("docker pull %s", resource.DockerRepo), true, true)
	if err != nil {
		return err
	}

	if !onlyDeploy {
		// helmify
		var cmds []string
		if resource.Type == "database" {
			// database
			if resource.Framework == "postgresql" {
				cmds = append(cmds,
					fmt.Sprintf("(cd %s; rm -rf deploy; helm pull oci://registry-1.docker.io/bitnamicharts/postgresql --untar && mv postgresql deploy)", name),
				)
			} else {
				cmds = append(cmds,
					fmt.Sprintf("(cd %s; rm -rf deploy; helm pull oci://registry-1.docker.io/bitnamicharts/redis --untar && mv redis deploy)", name),
				)
			}

		} else {
			// api or frontend
			cmds = append(cmds, fmt.Sprintf("(cd %s; rm -rf deploy; helm pull oci://registry-1.docker.io/rmedicharla/deploy --untar)", name))
		}

		cmds = append(cmds, fmt.Sprintf("echo 'connect using kubefs attach' > %s/deploy/templates/NOTES.txt", name))

		err = utils.RunMultipleCommands(cmds, true, true)
		if err != nil {
			return err
		}
	}

	if !onlyHelmify {
		// deploy
		var configs []string
		commandBuilder := strings.Builder{}
		if resource.Type == "database" {
			if resource.Framework == "postgresql" {
				configs = []string{
					"--set primary.persistence.size=" + fmt.Sprintf("%v", resource.Opts["persistence"]),
					"--set readReplicas.persistence.size=" + fmt.Sprintf("%v", resource.Opts["persistence"]),
					"--set primary.service.ports.postgresql=80",
					"--set readReplicas.service.ports.postgresql=80",
					"--set architecture=replication",
					"--set readReplicas.replicaCount=3",
					"--set auth.database=" + resource.Opts["default-database"],
					"--set auth.username=" + resource.Opts["user"],
					"--set auth.password=" + resource.Opts["password"],
					"--set namespaceOverride=" + name,
				}
			} else {
				configs = []string{
					"--set master.persistence.size=" + fmt.Sprintf("%v", resource.Opts["persistence"]),
					"--set replica.persistence.size=" + fmt.Sprintf("%v", resource.Opts["persistence"]),
					"--set master.service.ports.redis=80",
					"--set replica.service.ports.redis=80",
					"--set auth.password=" + resource.Opts["password"],
					"--set namespaceOverride=" + name,
				}
			}

			commandBuilder.WriteString(fmt.Sprintf("kubectl create namespace %s; helm upgrade --install %s %s/deploy", name, name, name))
		} else {
			// api or frontend
			configs = []string{
				"--set image.repository=" + resource.DockerRepo,
				"--set service.port=" + fmt.Sprintf("%v", resource.Port),
				"--set namespace=" + name,
			}

			if resource.Type == "api" {
				configs = append(configs,
					"--set readinessProbe.httpGet.path=/health",
					"--set livenessProbe.httpGet.path=/health",
					"--set service.type=ClusterIP",
					"--set ingress.enabled=false",
				)
			} else {
				configs = append(configs,
					"--set readinessProbe.httpGet.path=/",
					"--set livenessProbe.httpGet.path=/",
					"--set service.type=NodePort",
					"--set ingress.enabled=true",
					"--set ingress.host="+resource.Opts["host-domain"],
				)
			}

			// add all the resource hosts as env variables
			var count = 0
			for rName, r := range utils.ManifestData.Resources {
				if r.Type == "database" {
					configs = append(configs, fmt.Sprintf("--set env[%v].name=%sHOST_READ --set env[%v].value=%s", count, rName, count, r.ClusterHostRead))
					count++
				}
				configs = append(configs, fmt.Sprintf("--set env[%v].name=%sHOST --set env[%v].value=%s", count, rName, count, r.ClusterHost))
				count++
			}

			// add all the addon hosts as env variables
			for _, a := range resource.Dependents {
				addon, _ := utils.GetAddonFromName(a)
				configs = append(configs, fmt.Sprintf("--set env[%v].name=%sHOST --set env[%v].value=%s", count, a, count, addon.ClusterHost))
				count++
			}

			// add all the variables in .env as secrets
			envData, err := utils.ReadEnv(fmt.Sprintf("%s/.env", name))
			secrets := 0
			if err == nil {
				for _, line := range envData {
					configs = append(configs, fmt.Sprintf("--set secrets[%v].name=%s --set secrets[%v].value=%s --set secrets[%v].secretRef=%s-deploy-secret", secrets, strings.Split(line, "=")[0], secrets, strings.Split(line, "=")[1], secrets, name))
					secrets++
				}
			}

			// add all the kubefs env variables as secrets
			for key, value := range resource.Environment {
				configs = append(configs, fmt.Sprintf("--set secrets[%v].name=%s --set secrets[%v].value=%s --set secrets[%v].secretRef=%s-deploy-secret", secrets, key, secrets, value, secrets, name))
				secrets++
			}

			commandBuilder.WriteString(fmt.Sprintf("helm upgrade --install %s %s/deploy", name, name))
		}

		for _, c := range configs {
			commandBuilder.WriteString(fmt.Sprintf(" %s", c))
		}

		commands := []string{
			commandBuilder.String(),
		}

		err := deployToTarget(target, commands)
		if err != nil {
			return err
		}
	}

	return nil

}

var deployAllCmd = &cobra.Command{
	Use:   "all",
	Short: "kubefs deploy all - create helm charts & deploy the build targets onto the cluster for all resources",
	Long: `kubefs deploy all - create helm charts & deploy the build targets onto the cluster for all resources
example: 
	kubefs deploy all --flags,
	`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := utils.ValidateProject(); err != nil {
			utils.PrintError(err)
			return
		}

		var onlyHelmify, onlyDeploy bool
		onlyHelmify, _ = cmd.Flags().GetBool("only-helmify")
		onlyDeploy, _ = cmd.Flags().GetBool("only-deploy")
		target, _ := cmd.Flags().GetString("target")

		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		var errors []string
		var successes []string

		utils.PrintWarning(fmt.Sprintf("Deploying all resources & addons to %s", target))

		for name, resource := range utils.ManifestData.Resources {
			err := deployUnique(name, &resource, onlyHelmify, onlyDeploy, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deploying resource %s. %v", name, err))
				errors = append(errors, name)
				continue
			}

			successes = append(successes, name)
		}

		for name, addon := range utils.ManifestData.Addons {
			err := deployAddon(name, &addon, onlyHelmify, onlyDeploy, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deploying addon %s. %v", name, err))
				errors = append(errors, name)
				continue
			}
			successes = append(successes, name)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error deploying resource %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v deployed successfully", successes))
		}
	},
}

var deployResourceCmd = &cobra.Command{
	Use:   "resource [name ...]",
	Short: "kubefs deploy resource [name ...] - create helm charts & deploy the build targets onto the cluster for listed resource",
	Long: `kubefs deploy resource [name ...] - create helm charts & deploy the build targets onto the cluster for listed resource
example: 
	kubefs deploy resource <frontend> <api> <database> --flags,
	kubefs deploy resource <frontend> --flags
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

		var onlyHelmify, onlyDeploy bool
		onlyHelmify, _ = cmd.Flags().GetBool("only-helmify")
		onlyDeploy, _ = cmd.Flags().GetBool("only-deploy")
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

		var successes []string
		var errors []string

		utils.PrintWarning(fmt.Sprintf("Deploying resource %v to %s", args, target))
		utils.PrintWarning(fmt.Sprintf("Including addons %v", addonList))

		for _, name := range args {
			resource, err := utils.GetResourceFromName(name)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, name)
				continue
			}

			err = deployUnique(name, resource, onlyHelmify, onlyDeploy, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deploying resource %s. %v", name, err))
				errors = append(errors, name)
				continue
			}

			successes = append(successes, name)
		}

		for _, addon := range addonList {
			addonResource, err := utils.GetAddonFromName(addon)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, addon)
				continue
			}

			err = deployAddon(addon, addonResource, onlyHelmify, onlyDeploy, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deploying addon %s. %v", addon, err))
				errors = append(errors, addon)
				continue
			}

			successes = append(successes, addon)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error deploying resource %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v deployed successfully", successes))
		}
	},
}

var deployAddonCmd = &cobra.Command{
	Use:   "addons [name ...]",
	Short: "kubefs deploy addon [name ...] - create helm charts & deploy the build targets onto the cluster for listed addon",
	Long: `kubefs deploy addon [name ...] - create helm charts & deploy the build targets onto the cluster for listed addon
example:
	kubefs deploy addon <addon-name> <addon-name> --flags,
	kubefs deploy addon <addon-name> --flags,
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

		var onlyHelmify, onlyDeploy bool
		onlyHelmify, _ = cmd.Flags().GetBool("only-helmify")
		onlyDeploy, _ = cmd.Flags().GetBool("only-deploy")
		target, _ := cmd.Flags().GetString("target")

		err := utils.VerifyTarget(target)
		if err != nil {
			utils.PrintError(err)
			return
		}

		var successes []string
		var errors []string

		utils.PrintWarning(fmt.Sprintf("Deploying addons %v to %s", args, target))

		for _, addon := range args {
			addonResource, err := utils.GetAddonFromName(addon)
			if err != nil {
				utils.PrintError(err)
				errors = append(errors, addon)
				continue
			}

			err = deployAddon(addon, addonResource, onlyHelmify, onlyDeploy, target)
			if err != nil {
				utils.PrintError(fmt.Errorf("error deploying addon %s. %v", addon, err))
				errors = append(errors, addon)
				continue
			}

			successes = append(successes, addon)
		}

		if len(errors) > 0 {
			utils.PrintError(fmt.Errorf("error deploying resource %v", errors))
		}

		if len(successes) > 0 {
			utils.PrintInfo(fmt.Sprintf("Resource %v deployed successfully", successes))
		}
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployCmd.AddCommand(deployAllCmd)
	deployCmd.AddCommand(deployResourceCmd)
	deployCmd.AddCommand(deployAddonCmd)

	deployCmd.PersistentFlags().StringP("target", "t", "minikube", "target environment to deploy to ['minikube', 'gcp']")

	deployCmd.PersistentFlags().BoolP("only-helmify", "w", false, "only helmify the resources")
	deployCmd.PersistentFlags().BoolP("only-deploy", "d", false, "only deploy the resources")

	deployResourceCmd.Flags().StringP("with-addons", "a", "", "addons to be included in deployment (comma separated)")

}
