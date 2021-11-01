var mysql = require("mysql");

const host = process.env.DATABASE_HOST
var database = process.env.DATABASE_NAME
const dbuser = process.env.DATABASE_USER
const dbpassword = process.env.DATABASE_PWD

function closeMySQLConnection(connection) {

    return new Promise((resolve,reject) => {
        connection.end( err => {
            if ( err )
                return reject( err )
            resolve("Closed OK");
        })
    });
}

function runMySQLQuery(context, connection, query)
{
    return new Promise((resolve,reject ) => {

        connection.query(query, function (error, results, fields) {

            context.log("Running query: " + query); 

            if (error) 
            {
                context.log(error.message);

                context.res = {
                    status: 500,
                    body: error.message
                };

                reject(error);
            } else {

                context.log(results.message);

                context.res = {
                    body: "Query ran successfully."
                };
                resolve(context);
            }
        });
    });
}

/////////
// Azure Function main entry point
/////////
module.exports = async function (context, req) {
    context.log("Invoking Function to modify MySQL Database.");

    const setupaction = (req.query.setupaction || (req.body && req.body.setupaction));
    var query = "";

    switch(setupaction)
    {
        case "createdb":
            query = "CREATE DATABASE IF NOT EXISTS events;"
            break;
        case "createtable":
            query = "CREATE TABLE IF NOT EXISTS events (id varchar(255), title varchar(255), timestamp BIGINT, entries varchar(32765));";
            database = "events";
            break;
        case "cleartable":
            // clear the events table
            query = "DELETE FROM events";
            database = "events";
            break;
    }

    if(query.length !== 0)
    { 
        
        var connection = mysql.createConnection({
            host     : host,
            user     : dbuser,
            password : dbpassword,
            database : database,
            ssl: true
        });

        connection.connect();
        await runMySQLQuery(context, connection, query);
        await closeMySQLConnection(connection);
    }

    context.done();

};