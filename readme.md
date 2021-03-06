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
| Bicep / ARM ([docs](https://docs.microsoft.com/azure/azure-resource-manager/bicep/overview)) | CloudFormation |
| Cosmos DB ([docs](https://docs.microsoft.com/azure/cosmos-db/introduction))| DynamoDB |
| Event Hub ([docs](https://docs.microsoft.com/azure/event-hubs/event-hubs-about)) | Kinesis |
| Functions ([docs](https://docs.microsoft.com/azure/azure-functions/functions-overview)) | Lambda |
| Database for MySQL ([docs](https://docs.microsoft.com/azure/mysql/overview)) | RDS (MySQL) |
| Application Insights ([docs](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)) | X-Ray |
| Key Vault ([docs](https://docs.microsoft.com/azure/key-vault/general/overview)) | Secrets Manager |
| GitHub Actions ([docs](https://docs.github.com/actions)) | CodeDeploy |
| Virtual Network ([docs](https://docs.microsoft.com/azure/virtual-network/virtual-networks-overview)) | VPC |
| Private Link Endpoint ([docs](https://docs.microsoft.com/azure/private-link/private-link-overview)) | VPC endpoint |

We have multiple methods to deploy code into Azure, but for simplicity we are using GitHub Actions so our CI/CD pipeline definition lives with this sample, making it more straightforward to clone the repository and get started.

## Data flow

The Azure Function is triggered by new events arriving within the Azure Event Hub. In our sample the `client-app` program is used to create these events and send them in a batch.

The Azure Function [Event Hub trigger](https://docs.microsoft.com/azure/azure-functions/functions-bindings-event-hubs) is using the default settings for batch size so one or more events will be received and processed by the Node.js code of the Azure Function.

The processed data is then persisted to both the Azure Database for MySQL instance and the Cosmos DB Container.

## Functionality (Ranking and Stats)

The behaviour of this solution is exactly the same as that described in the original sample. Read more about them here: [Ranking](https://github.com/awsdocs/aws-lambda-developer-guide/tree/main/sample-apps/list-manager#ranking) and [Stats](https://github.com/awsdocs/aws-lambda-developer-guide/tree/main/sample-apps/list-manager#stats).

## Prerequisites

This sample application is compatible with [LTS versions of Node.js](https://nodejs.org/about/releases/). You will need both Node.js and npm installed. We used Node 14 for development.

You need the [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed as it will give you the tools you need to deploy and configure the services used in Azure.

We use the [GitHub CLI](https://github.com/cli/cli) to configure the Action used to deploy our Azure Function code into Azure. You will need to configure a Personal Acces Token (PAT) for use - [follow the GitHub documentation on how](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). Ensure to select `workflow` and `read:org` scopes. Copy the PAT once generated.

The code and sample application was authored on Ubuntu running on Windows Subsystem for Linux (WSL), but should work across any Linux distro or MacOS. Apart from the small amount of shell scripting we use there is nothing here that will stop the majority of this sample from being run on a Windows PC.

Finally, you need an Azure subscription to deploy this solution - a [free Subscription](https://azure.com/free) should suffice.

## Setup

Start by forking this repository on GitHub. Once forked, clone the repository to your local developer machine, or open in a GitHub Codespace.

```bash
$ git clone https://github.com/your_user/azure-list-manager-sample.git
$ cd azure-list-manager-sample
```

Start by deploying the necessary Azure services by using the [Bicep file](infra-deploy/deploy.bicep) contained in the infra-deploy folder. You will need to use the Azure CLI and log into your Subscription first.

You will need to select an Azure Region when deploying. You should supply the `Name` of the Region which can be obtained using this Azure CLI command:  
`az account list-locations -o table`.

It is also recommended to create a relatively short Resource Group name as this name is used as the seed for a random string suffix that is used for all created Resources. If you create a long Resource Group name you may run into issues with Resource naming length restrictions.

```bash
$ az login
$ az group create --location your_region --resource-group your_group_name
$ az deployment group create --resource-group your_group_name --template-file infra-deploy/deploy.bicep --query properties.outputs
```

You will be prompted for a strong password for the MySQL admin user and then the deployment will commence.

Depending on the Region, and time of day, the template will take around 10 minutes to deploy. You should receive no errors. If you do, please [open an issue](https://github.com/sjwaight/azure-list-manager-sample/issues) on the origianl repository so we can take a look - please make sure to include your error message.

The Bicep file will deploy all resources, as well as setting up the following items:

- A User-Assigned [Managed Service Identity](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview) (MSI) which will be used by the Azure Function to read Secrets from the Azure Key Vault
- Create the necessary Azure Key Vault Secrets used by the Azure Function
- Set the MSI for the Azure Function, and grant it access to read Secrets from the Azure Key Vault
- Configure all infrastructure to connect only via a private Virtual Network.

When deployment is completed you will have five outputs displayed on screen as shown below.

```json
{
  "deployed_location": {
    "type": "String",
    "value": "westus2"
  },
  "deployed_resource_group": {
    "type": "String",
    "value": "listmansample"
  },
  "event_hub_client_connection": {
    "type": "String",
    "value": "Endpoint=sb://lstmnnsh3eesgx7nhypc.servicebus.windows.net/;SharedAccessKeyName=SendEvents;SharedAccessKey=SECURE_KEY_HERE;EntityPath=clientevents"
  },
  "event_hub_name": {
    "type": "String",
    "value": "clientevents"
  },
  "function_app_name": {
    "type": "String",
    "value": "lmfunch3eesgx7nhypc"
  }
}
```

- `event_hub_client_connection` - the connection string to use with the `client-app` to publish events.
- `event_hub_name` - the event hub name to use with the `client-app` to publish events.
- `deployed_location` - the Azure Region to which the resources were deployed.
- `deployed_resource_group` - the Azure Resource Group name where all the resources were deployed.
- `function_app_name` - the name of the Function App that was deployed.

### Configure and run GitHub deployment

We first need to enable the GitHub Action workflows for the forked repository via a web browser. Navigate to the Actions tab and when prompted click **I understand my workflows, go ahead and enable them**. At present you cannot enable workflows from the GitHub CLI when the repository has first been forked.

![Enabled GitHub Actions on a forked repository](images/2021-11-21_16-30-45.png)

Return to the command line and log into the GitHub CLI. You will need your previously created GitHub Personal Access Token (PAT) for this.

```bash
$ gh auth login
```

When prompted, select GitHub.com > HTTPS > Use Git Credentials (no) > Paste an authentication token.

We have to update one placeholder in the GitHub Action worfklow and set one repository secret for the build and deploy to work. 

The deployment expects a Publishing Profile for the Azure Function to be held in the secret which will need to set by calling the Azure API to reteive the Profile.

Use the the output values for `function_app_name` and `deployed_resource_group` from the earlier Bicep deployment in the command as follows.

```bash
$ gh secret set AZURE_APP_SERVICE_PUB_PROFILE --body "$(az functionapp deployment list-publishing-profiles --name function_app_name --resource-group deployed_resource_group --xml)"
```

Finally, we need to edit the GitHub Action workflow file and set the `app-name` property for the `Run Azure Functions Action` step to match the value for `function_app_name`.

Open the [main_listmanfunction.yml](.github/workflows/main_listmanfunction.yml) file in your favourite editor and change the appropriate line (marked below). Save the file, commit and push to GitHub.

```yaml
      - name: 'Run Azure Functions Action'
        uses: Azure/functions-action@v1
        id: fa
        with:
          app-name: 'function_app_name'  << ** UPDATE THIS VALUE **
          slot-name: 'Production'
          package: ${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
          publish-profile: ${{ secrets.AZURE_APP_SERVICE_PUB_PROFILE }}
```

Pushing the updated workflow will cause the GitHub Action to run. Once it has completed you should find that your Azure Function code has been deployed.

You can check that both Functions were deployed by using the following Azure CLI commands. Both commands should return without error. It may take up to a minute for the Functions to show up in the reponse.

```bash
az functionapp function show --resource-group deployed_resource_group --name function_app_name --function-name dbadmin
az functionapp function show --resource-group deployed_resource_group --name function_app_name --function-name processor
```

### Configure MySQL

As the Azure Database for MySQL instance we are using isn't available from a public network we have to use the `dbadmin` Azure Function as our way to initiliase the database.

First we need to get the URL and key for the `dbadmin` Azure Function so we can invoke it. Don't forget to change the placeholders `function_app_name` and `deployed_resource_group`. We will store the output in to environment variables we use below.

```bash
$ FUNC_URL=$(az functionapp function show --resource-group deployed_resource_group --name function_app_name --function-name dbadmin --query invokeUrlTemplate --output tsv)
$ FUNC_KEY=$(az functionapp function keys list --resource-group deployed_resource_group --name function_app_name --function-name dbadmin --query default --output tsv)
```

Now we have the URL and key for our Function in variables we can use them and curl to create our MySQL database and table.

```bash
$ curl "$FUNC_URL?code=$FUNC_KEY&setupaction=createdb"
$ curl "$FUNC_URL?code=$FUNC_KEY&setupaction=createtable"
```

If the command succeeded you should receive `Query ran successfully` back as a response.

> Note: You can empty the MysQL table by calling the same URL with a 'setupaction' argument of `cleartable`.

## Test

At the commandline, switch to the [client-app](./client-app/readme.md) folder and create a new `.env` file and populate its values using the `event_hub_client_connection` and `event_hub_name` outputs from our Bicep deployment.

```bash
$ cd client-app
$ cp sample.env .env
```

Edit the .env file if a text editor so it looks similar to this sample.

```bash
# Replace with your value from Bicep deployment
EVENTHUB_CONNECTION_STRING="Endpoint=sb://lstmnnsh3eesgx7nhypc.servicebus.windows.net/;SharedAccessKeyName=SendEvents;SharedAccessKey=SECURE_KEY_HERE;EntityPath=clientevents"
EVENTHUB_NAME="clientevents"
```

Save the file and you are ready to publish events to Azure Event Hub.

```bash
$ node sendEvents.js
```

We are using auto-instrumentation with our Azure Function so we get some insights on what is happening when our data is processed. Open the Azure Portal and navigate to your Resource Group and open the Application Insights associated with your application.

![Appplication Insights Instance](images/2021-11-20_16-59-51.png)

You will then see an overview of the application. On this screen click on the peak of the Server Requests graph which will take you to the Performance view.

![Appplication Insights Server Requess](images/2021-11-20_16-53-46.png)

The Performance view allows you to investigage bottlenecks and slow dependencies as required.

![Appplication Insights Performance](images/2021-11-20_17-05-17.png)

At time of writing the Application Insights SDK for Node.js doesn't have dedicated instrumentation support for MySQL for the MySQL library we are using and also Cosmos DB, though we do see the underlying HTTP calls occuring and can dig into them if required. 

## Cleanup

To delete your application you can simply delete the Azure Resource Group.

```bash
$ az group delete --resource-group your_group_name --yes
```