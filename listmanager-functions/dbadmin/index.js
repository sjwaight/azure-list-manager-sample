var mysql = require("mysql2/promise");
var fs = require('fs');

const host = process.env.DATABASE_HOST;
const database = process.env.DATABASE_NAME;
var connect_database = "mysql";
const dbuser = process.env.DATABASE_USER;
const dbpassword = process.env.DATABASE_PWD;

const cacert = fs.readFileSync("BaltimoreCyberTrustRoot.crt.pem");

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
            query = "CREATE DATABASE IF NOT EXISTS " + database + ";"
            break;
        case "createtable":
            query = "CREATE TABLE IF NOT EXISTS events (id varchar(255), title varchar(255), eventtime timestamp, entries varchar(32765));";
            connect_database = database;
            break;
        case "cleartable":
            query = "DELETE FROM events";
            connect_database = database;
            break;
    }

    if(query.length !== 0)
    { 
        try
        {
            var connection = await mysql.createConnection({
                host     : host,
                user     : dbuser,
                password : dbpassword,
                database : connect_database,
                waitForConnections: true,
                ssl: {
                    rejectUnauthorized: true,
                    ca: cacert   
                }
            });

            await connection.connect();
            await connection.query(query);

            context.log("Query ran successfully.");
            context.res = {
                body: "Query ran successfully."
            };
                    
            await connection.end();
        } 
        catch (error)
        {
            context.log.error('Error calling MySQL', error);
            context.res = {
                body: "Query failed.",
                status: 500
            };
        }
    }
    else
    {
        context.res = {
            body: "No matching query."
        };
    }
    context.done();
};