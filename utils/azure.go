package utils

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armsubscriptions"
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
