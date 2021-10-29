# Sample Message Sender

This Node.js sample program is designed to send 4 test events to an Event Hub. This program is designed to mirror the `put-records.sh` script that ships as part of the [AWS List Manager Node.js Lambda sample](https://docs.aws.amazon.com/lambda/latest/dg/samples-listmanager.html) which we are rebuilding for Azure to demonstrate the setps required to decouple development from AWS.

## Prerequisites

This sample program is compatible with [LTS versions of Node.js](https://nodejs.org/about/releases/).

You need an Azure subscription and an Azure Event Hub configured to receive events. It is strongly recommended you setup a Shared Access Policy that allows only 'send' permissions and use that for this client application.

The sample retrieve credentials to access the service endpoint from environment variables. Alternatively, edit the source code to include the appropriate credentials. See each individual sample for details on which environment variables/credentials it requires to function.

## Setup

To run the samples using the published version of the package:

1. Install the dependencies using `npm`:

```bash
npm install
```

2. Edit the file `sample.env`, adding the correct credentials to access the Azure service and run the samples. Then rename the file from `sample.env` to just `.env`. The sample programs will read this file automatically.

3. Run the sample:

```bash
node sendEvents.js
```

Alternatively, run a single sample with the correct environment variables set (setting up the `.env` file is not required if you do this), for example (cross-platform):

```bash
npx cross-env EVENTHUB_CONNECTION_STRING="<eventhub connection string>" EVENTHUB_NAME="<eventhub name>" node sendEvents.js
```