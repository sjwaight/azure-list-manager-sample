// automatically uses process.env.APPINSIGHTS_INSTRUMENTATIONKEY
let appInsights = require("applicationinsights");
appInsights.setup().start(); 

var mysql = require("mysql2/promise");
var md5 = require('md5');
var fs = require('fs');

const { CosmosClient } = require("@azure/cosmos");

const host = process.env.DATABASE_HOST
var database = process.env.DATABASE_NAME
const dbuser = process.env.DATABASE_USER
const dbpassword = process.env.DATABASE_PWD
const dbtable = "events"

const cosmosconnection = process.env.COSMOS_CONNECTION
const cosmosdatabase = process.env.COSMOS_DATABASE
const cosmoscontainer = process.env.COSMOS_CONTAINER

const cacert = fs.readFileSync("BaltimoreCyberTrustRoot.crt.pem");

// Calculate results and store in Cosmos DB
var updateList = async function(context, event){
    // shallow copy of event
    let item = { ... event };

    // aggregate ID (all entries with same title)
    var aggid = md5(item.title + "agg");
    // individual ID (from same user only)
    item.id = md5(item.title + item.user);
    // as we use a single container we can differentatiate documents using a custom attribute
    //item.doctype = "rawdata";
    item.entries = JSON.parse(item.entries);

    const client = new CosmosClient(cosmosconnection);
    var datacontainer = client.database(cosmosdatabase).container(cosmoscontainer);

    // get agg item
    var aggdata = await datacontainer.items.query({
      query: "SELECT * from a WHERE a.id = @itemid",
      parameters: [{name: "@itemid", value: aggid }]
    }).fetchNext();
  
    // get indv item
    var data = await datacontainer.items.query({
      query: "SELECT * from a WHERE a.id = @itemid",
      parameters: [{name: "@itemid", value: item.id }]
    }).fetchNext();
 
    var newEntries = JSON.parse(event.entries);
    var oldEntries = {};
    var aggregateEntries = {};
    var aggItem = {};

    if (data.resources.length > 0)
    {
      context.log("DATA: " + JSON.stringify(data.resources[0], null, 2));
      oldEntries = data.resources[0].entries;
    }

    if (aggdata.resources.length > 0) {
      context.log("AGGDATA: " + JSON.stringify(aggdata.resources[0], null, 2));
      aggregateEntries = aggdata.resources[0].entries;
      aggItem = aggdata.resources[0];
    } 
    else 
    {
      aggItem.id = aggid;
      aggItem.title = item.title;
      aggItem.type = item.type;
    }

    // TODO: store contributor user IDs in aggregate item and confirm their presence before applying delta
    var deltaEntries = newEntries
    context.log("NEW ENTRIES: " + JSON.stringify(newEntries, null, 2));
    context.log("OLD ENTRIES: " + JSON.stringify(oldEntries, null, 2));

    if (event.type == "rank" ) {
      // calculate changes vs existing indv list
      Object.keys(newEntries).forEach(function(key,index) {
        if (oldEntries.hasOwnProperty(key))
          deltaEntries[key] -= oldEntries[key];
      })
      Object.keys(oldEntries).forEach(function(key,index) {
        if (!newEntries.hasOwnProperty(key))
          deltaEntries[key] = -oldEntries[key];
      })
      // update aggregate list
      Object.keys(deltaEntries).forEach(function(key,index) {
        if (aggregateEntries.hasOwnProperty(key))
          aggregateEntries[key] += deltaEntries[key];
        else
          aggregateEntries[key] = newEntries[key];
      })
    }

    if ( event.type == "tally" ) {
      // update existing indv list
      Object.keys(newEntries).forEach(function(key,index) {
        //TODO: check type of value = number
        if (oldEntries.hasOwnProperty(key))
          oldEntries[key] += newEntries[key];
        else
          oldEntries[key] = newEntries[key];
      })
      Object.keys(deltaEntries).forEach(function(key,index) {
        if (aggregateEntries.hasOwnProperty(key))
          aggregateEntries[key] += deltaEntries[key];
        else
          aggregateEntries[key] = newEntries[key];
      })
      item.entries = oldEntries; // JSON.stringify(oldEntries, null, 0);
      context.log("TALLIED ENTRIES: " + JSON.stringify(item.entries, null, 0));
    }

    context.log("DELTA ENTRIES: " + JSON.stringify(deltaEntries, null, 0));
     
    await datacontainer.items.upsert(item);
  
    aggItem.entries = aggregateEntries; // JSON.stringify(aggregateEntries, null, 0);
    context.log("AGGREGATE ENTRIES: " + JSON.stringify(aggItem.entries, null, 0));
  
    await datacontainer.items.upsert(aggItem);
}
  
// Store the event in MySQL database
var storeEvent = async function(context, event, connection){
  // update database
  var query = "INSERT INTO " + dbtable + " (id, title, eventtime, entries) VALUES ?;"
  var values = [[event.id, event.title, new Date(event.timestamp), event.entries]]
  context.log("Storing event in MySQL:" + event.id + "," + event.title  + "," + event.timestamp  + "," + event.entries);

  return await connection.query(query, [values]).catch(error => context.log(error));
}
  
var processRecords = async function(context, eventHubMessages, connection) {

    var count = 0;

    return new Promise((resolve,reject) => {
      eventHubMessages.forEach(async (message, index) => {

        const item = JSON.parse(message)

        var event = {}
        event.title = item.title;
        event.user = item.user;
        event.type = item.type;
        event.entries = JSON.stringify(item.entries, null, 0);
        event.id = context.bindingData.sequenceNumberArray[count];
        event.timestamp = context.bindingData.enqueuedTimeUtcArray[count];

        context.log("EVENT TIMESTAMP:" + event.timestamp);

        try
        {
          await updateList(context, event);
          await storeEvent(context, event, connection);
        }
        catch (error)
        {
          context.log.error("Error writing data", error);
          reject(error);
        }
        count++;

        context.log("MESSAGE PROCESS COUNT: " + count);
      });
      resolve();
    });
}

/////////
// Azure Function main entry point
/////////
module.exports = async function (context, eventHubMessages) {

    context.log("Eventhub messages triggered Function.");

    try 
    {
      var connection = await mysql.createConnection({
          host     : host,
          user     : dbuser,
          password : dbpassword,
          database : database,
          waitForConnections: true,
          ssl: {
              rejectUnauthorized: true,
              ca: cacert   
          }
        });
  
      await connection.connect();

      await processRecords(context, eventHubMessages, connection);

      await connection.end();
    } 
    catch (error)
    {
      context.log.error('Error', error);
    }
    
    context.done();
};