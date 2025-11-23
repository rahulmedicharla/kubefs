package utils

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/containerservice/armcontainerservice"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armsubscriptions"
	"github.com/rahulmedicharla/kubefs/types"
)

func AuthenticateAzure() error {
	commands := []string{
		"brew install azure-cli",
		"az login",
	}

	err := RunMultipleCommands(commands, true, true)
	if err != nil {
		return err
	}

	return nil
}

func GetAzureClusterContext(config *types.CloudConfig) error {
	return RunCommand(fmt.Sprintf("az aks get-credentials --resource-group %s --name %s --overwrite-existing", config.ResourceGroup, config.MainCluster), true, true)
}

func VerifyAzureSubscription(ctx context.Context, cred *azidentity.DefaultAzureCredential, subscription string) error {
	sClient, err := armsubscriptions.NewClient(cred, nil)
	if err != nil {
		return err
	}

	_, err = sClient.Get(ctx, subscription, nil)
	if err != nil {
		return err
	}

	return nil
}

func VerifyAzureResourceGroup(ctx context.Context, cred *azidentity.DefaultAzureCredential, subscription string, resourceGroup string) error {
	clientFactory, err := armresources.NewClientFactory(subscription, cred, nil)
	if err != nil {
		return err
	}

	rgClient := clientFactory.NewResourceGroupsClient()

	resp, err := rgClient.CheckExistence(ctx, resourceGroup, nil)
	if err != nil {
		return err
	}

	if !resp.Success {
		return fmt.Errorf("resource group %s doesn't exist in Azure", resourceGroup)
	}

	return nil
}

func VerifyAzureLocation(ctx context.Context, cred *azidentity.DefaultAzureCredential, subscription string, region string) error {
	client, err := armsubscriptions.NewClient(cred, nil)
	if err != nil {
		return err
	}

	pager := client.NewListLocationsPager(subscription, nil)

	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return err
		}
		for _, v := range page.Value {
			if *v.Name == region {
				return nil
			}
		}
	}

	return fmt.Errorf("provided region is invalid %s", region)
}

func EnableAzureProviders(ctx context.Context, cred *azidentity.DefaultAzureCredential, subscription string, providers []string) error {
	clientFactory, err := armresources.NewClientFactory(subscription, cred, nil)
	if err != nil {
		return err
	}
	providersClient := clientFactory.NewProvidersClient()

	for _, providerNamespace := range providers {
		_, err = providersClient.Register(ctx, providerNamespace, nil)
		if err != nil {
			return fmt.Errorf("failed to register %s: %w", providerNamespace, err)
		}
	}

	return nil
}

func StartAzureCluster(config *types.CloudConfig, clusterName string) error {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return err
	}

	client, err := armcontainerservice.NewManagedClustersClient(config.SubscriptionId, cred, nil)
	if err != nil {
		return err
	}

	ctx := context.Background()
	poller, err := client.BeginStart(ctx, config.ResourceGroup, clusterName, nil)
	if err != nil {
		return err
	}

	var resp *http.Response
	for !poller.Done() {
		resp, err = poller.Poll(ctx)
		if err != nil {
			return err
		}

		PrintWarning(fmt.Sprintf("Waiting for Azure cluster starting to complete... %s", resp.Status))
		time.Sleep(30 * time.Second)
	}

	return nil
}

func PauseAzureCluster(config *types.CloudConfig, clusterName string) error {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return err
	}

	client, err := armcontainerservice.NewManagedClustersClient(config.SubscriptionId, cred, nil)
	if err != nil {
		return err
	}

	ctx := context.Background()
	poller, err := client.BeginStop(ctx, config.ResourceGroup, clusterName, nil)
	if err != nil {
		return err
	}

	var resp *http.Response
	for !poller.Done() {
		resp, err = poller.Poll(ctx)
		if err != nil {
			return err
		}

		PrintWarning(fmt.Sprintf("Waiting for Azure cluster pausing to complete... %s", resp.Status))
		time.Sleep(30 * time.Second)
	}

	return nil
}

func ProvisionAzureCluster(config *types.CloudConfig, clusterName string) error {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return err
	}

	client, err := armcontainerservice.NewManagedClustersClient(config.SubscriptionId, cred, nil)
	if err != nil {
		return err
	}

	ctx := context.Background()
	poller, err := client.BeginCreateOrUpdate(ctx,
		config.ResourceGroup,
		clusterName,
		armcontainerservice.ManagedCluster{
			Location: to.Ptr(config.Region),
			Identity: &armcontainerservice.ManagedClusterIdentity{
				Type: to.Ptr(armcontainerservice.ResourceIdentityTypeSystemAssigned),
			},
			Properties: &armcontainerservice.ManagedClusterProperties{
				AgentPoolProfiles: []*armcontainerservice.ManagedClusterAgentPoolProfile{
					{
						Name:   to.Ptr("nodepool1"),
						Count:  to.Ptr[int32](1),
						VMSize: to.Ptr("standard_dc2as_v5"), // Choose a standard VM size
						Mode:   to.Ptr(armcontainerservice.AgentPoolModeSystem),
						OSType: to.Ptr(armcontainerservice.OSTypeLinux),
					},
				},
				DNSPrefix: to.Ptr(clusterName),
			},
		},
		nil,
	)

	if err != nil {
		return err
	}

	var resp *http.Response
	for !poller.Done() {
		resp, err = poller.Poll(ctx)
		if err != nil {
			return err
		}

		PrintWarning(fmt.Sprintf("Waiting for Azure cluster creation to complete... %s", resp.Status))
		time.Sleep(30 * time.Second)
	}

	PrintInfo(fmt.Sprintf("Azure cluster [%s] created successfully... Installing dependencies...", clusterName))

	commands := []string{
		fmt.Sprintf("az aks get-credentials --resource-group %s --name %s --overwrite-existing", config.ResourceGroup, clusterName),
		"helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx",
		"helm repo update",
		"helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace ingress-nginx --set controller.service.annotations.service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path=/healthz --set controller.service.externalTrafficPolicy=Local > /dev/null",
		"kubectl wait --for=condition=available --timeout=5m deployment/ingress-nginx-controller -n ingress-nginx",
	}

	return RunMultipleCommands(commands, true, true)
}

func DeleteAzureCluster(config *types.CloudConfig, clusterName string) error {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return err
	}

	client, err := armcontainerservice.NewManagedClustersClient(config.SubscriptionId, cred, nil)
	if err != nil {
		return err
	}

	ctx := context.Background()
	poller, err := client.BeginDelete(ctx, config.ResourceGroup, clusterName, nil)
	if err != nil {
		return err
	}

	var resp *http.Response
	for !poller.Done() {
		resp, err = poller.Poll(ctx)
		if err != nil {
			return err
		}

		PrintWarning(fmt.Sprintf("Waiting for Azure cluster deletion to complete... %s", resp.Status))
		time.Sleep(30 * time.Second)
	}

	return nil
}

func SetupAzure(ctx context.Context, subscription string) (*string, *string, error) {
	//
	// Setup Azure project by verifying subscription & resource group existence
	//

	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return nil, nil, err
	}

	err = VerifyAzureSubscription(ctx, cred, subscription)
	if err != nil {
		return nil, nil, err
	}

	var resourceGroup string
	err = ReadInput("Enter the AZ Resource group to use: ", &resourceGroup)
	if err != nil {
		return nil, nil, err
	}

	err = VerifyAzureResourceGroup(ctx, cred, subscription, resourceGroup)
	if err != nil {
		return nil, nil, err
	}

	var region string
	err = ReadInput("Enter the AZ Location to interact with: ", &region)
	if err != nil {
		return nil, nil, err
	}

	err = VerifyAzureLocation(ctx, cred, subscription, region)
	if err != nil {
		return nil, nil, err
	}

	// Enable required services
	services := []string{
		"Microsoft.Compute",
		"Microsoft.ContainerService",
		"Microsoft.Network",
		"Microsoft.Storage",
	}

	err = EnableAzureProviders(ctx, cred, subscription, services)
	if err != nil {
		return nil, nil, fmt.Errorf("error enabling Azure services: %v", err)
	}

	return &resourceGroup, &region, nil
}
