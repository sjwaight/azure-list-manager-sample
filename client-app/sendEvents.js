require('dotenv').config(); 

const { EventHubProducerClient } = require("@azure/event-hubs");

// Define connection string and related Event Hubs entity name here
const connectionString = process.env.EVENTHUB_CONNECTION_STRING || "";
const eventHubName = process.env.EVENTHUB_NAME || "";

async function main() {

    // Create a producer client to send messages to the event hub.
    const producer = new EventHubProducerClient(connectionString, eventHubName);

    // Prepare a batch of events.
    const batch = await producer.createBatch();
    batch.tryAdd({ body: '{"title": "favourite movies", "user": "simon", "type": "rank", "entries": {"blade runner": 2, "the empire strikes back": 3, "alien": 1}}'});
    batch.tryAdd({ body: '{"title": "stats", "user": "beth", "type": "tally", "entries": {"xp": 25}}' });
    batch.tryAdd({ body: '{"title": "favourite movies", "user": "mike", "type": "rank", "entries": {"blade runner": 1, "the empire strikes back": 2, "alien": 3}}' });    
    batch.tryAdd({ body: '{"title": "stats", "user": "bill", "type": "tally", "entries": {"xp": 83}}' });

      // Send the batch to the event hub.
    await producer.sendBatch(batch);

    // Close the producer client.
    await producer.close();

    console.log("A batch of " + batch.count + " events have been sent to the event hub");
}

main().catch((err) => {
  console.log("Error occurred: ", err);
});