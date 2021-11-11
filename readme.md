# Sample list manager application, but on Azure

This sample application processes events from an Azure Event Hub stream to create and update lists. It uses an Azure Virtual Network and Azure Private Link Endpoints as a secure inter-service transport method, giving the Azure Function access to both Azure Cosmos Database (with SQL API configured) and the Azure Database for MySQL services. The application also uses Azure Key Vault, Application Insights and GitHub Actions.

![Architecture](images/2021-10-29_14-03-48.png)

This repository contains the following resources:

- `listmanager-functions` - a single Azure Function that has two Functions:
    - `dbadmin` - a Node.js Function that can be used to run SQL commands against the MySQL server.
    - `processor` - a Node.js Function tha processes events from the Event Hub.
- `client-app` - a Node.js client application that is used to publish events onto the Event Hub.
- `infra-deploy` - contains a Bicep file that is used to provision the required Azure infrastructure.

If you are visiting here to understand how this service has been migrated from AWS to Azure here are the service mappings between the two platforms.

| Azure | AWS |
|----|----|
| Cosmos DB | DynamoDB |
| Event Hub | Kinesis |
| Functions | Lambda |
| Database for MySQL | RDS (MySQL) |
| Application Insights | X-Ray |
| Key Vault | Secrets Manager |
| GitHub Actions | CodeDeploy |
| Virtual Network | VPC |
| Private Link Endpoint | VPC endpoint |

There are some functional differences between services which we'll take a look at later. We also have multiple methods to deploy code into Azure, but for the purpose of simplicity we are using GitHub Actions here as the deployment definition lives with this sample, making much more straightforward to clone and get started.

We are using the Azure Functions v3 runtime for this sample.

## Data flow

The Azure Function is triggered by new events arriving within the Azure Event Hub. In our sample the `client-app` program is used to create these events and send them in a batch.

The Azure Function [Event Hub trigger](https://docs.microsoft.com/azure/azure-functions/functions-bindings-event-hubs) is using the default settings for batch size so one or more events will be received and processed by the Node.js code of the Azure Function.

The processed data is then persisted to both the Azure Database for MySQL instance and the Cosmos DB Container. We have collapsed the two tables used in the original sample as the use of individual Containers to represent Tables in Cosmos DB is an anti-pattern.

## Functionality (Ranking and Stats)

The behaviour of this solution is exactly the same as that described in the for [Ranking](https://github.com/awsdocs/aws-lambda-developer-guide/tree/main/sample-apps/list-manager#ranking) and [Stats](https://github.com/awsdocs/aws-lambda-developer-guide/tree/main/sample-apps/list-manager#stats).

## Prerequisites

This sample application is compatible with [LTS versions of Node.js](https://nodejs.org/about/releases/). You will need both Node.js and npm installed. We used Node 14 for development.

You need the [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed as it will give you the tools you need to deploy and configure the services used in Azure.

We use the [GitHub CLI](https://github.com/cli/cli) to configure the Action used to deploy our Azure Function code into Azure. You will need to configure a Personal Acces Token (PAT) for use - [follow the GitHub documentation on how](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). Ensure to select `workflow` and `read:org` scopes. Copy the PAT once generated.

The code and sample application was authored on Ubuntu running on Windows Subsystem for Linux (WSL), but should work across any Linux distro or MacOS. We haven't tested on Windows, but there is nothing here that should stop the code from running.

Finally, you need an Azure subscription to deploy this solution - a [free Subscription](https://azure.com/free) should suffice.

## Setup

Start by forking this repository into your own on GitHub. Once forked, then clone the repository to your local developer machine, or open in a GitHub Codespace.

```
$ git clone https://github.com/your_user/azure-list-manager-sample.git
$ cd azure-list-manager-sample
```

Start by deploying the necessary Azure services by using the bicep file. You will need to use the Azure CLI and log into your Subscription first.

>> Note: you will need to select an Azure Region when deploying. You should supply the `Name` of the Region which can be obtained using this Azure CLI command: 

>> `az account list-locations -o table`

```
$ az login
$ az group create --location your_region --resource-group your_group_name
$ az deployment group create --resource-group your_group_name --template-file infra-deploy/deploy.bicep --query properties.outputs -o table
```

You will be prompted for a strong password for the MySQL admin user and then the deployment will commence.

Depending on the Region, and time of day, the template will take around 10 minutes to deploy. You should receive no errors. If you do, please [open an issue](https://github.com/sjwaight/azure-list-manager-sample/issues) on the origianl repository so we can take a look - please make sure to include your error message.

The bicep file will deploy all resources, as well as setting up the following items:

- A User-Assigned [Managed Service Identity](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview) (MSI) which will be used by the Azure Function to read Secrets from the Azure Key Vault
- Create the necessary Azure Key Vault Secrets used by the Azure Function
- Set the MSI for the Azure Function, and grant it access to read Secrets from the Azure Key Vault
- Configure all infrastructure to connect only via a private Virtual Network.

When deployment is completed you will have five outputs displayed on screen:

- `event_hub_client_connection` - the connection string to use with the `client-app` to publish events.
- `event_hub_name` - the event hub name to use with the `client-app` to publish events.
- `deployed_location` - the Azure Region to which the resources were deployed.
- `deployed_resource_group` - the Azure Resource Group name where all the resources were deployed.
- `function_app_name` - the name of the Function App that was deployed.

### Configure and run GitHub deployment

Start by logging into the GitHub CLI. You will need your previously created GitHub Personal Access Token for this.

```
$ gh auth login
```

When prompted, select - GitHub.com - HTTPS - Git Credentials (no) - Paste an authentication token.

We have to set one repository secret for the GitHub Action for the Azure Function to work. The deployment expects a Publishing Profile for the Function to be held in the secret.

Use the the output values for `function_app_name` and `deployed_location` from the bicep deployment in the command as follows. If the update succeeds then the worklow can be triggered using the second comand shown.

```
$ gh secret set AZURE_APP_SERVICE_PUB_PROFILE --body "$(az functionapp deployment list-publishing-profiles --name function_app_name --resource-group deployed_location)"
$ gh workflow run
```

When prompted, select the GitHub Action workflow for the current repository and a run will be triggered on GitHub and the Azure Function code will be deployed into Azure.
