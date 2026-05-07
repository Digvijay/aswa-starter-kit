const { app } = require('@azure/functions');
const { DefaultAzureCredential } = require('@azure/identity');
const { CosmosClient } = require('@azure/cosmos');

// No connection strings. Endpoint + managed identity only.
const endpoint = process.env.COSMOS_ENDPOINT;
const databaseName = process.env.COSMOS_DATABASE || 'app';
const containerName = process.env.COSMOS_CONTAINER || 'items';

let container;
function getContainer() {
  if (!container && endpoint) {
    const client = new CosmosClient({
      endpoint,
      aadCredentials: new DefaultAzureCredential()
    });
    container = client.database(databaseName).container(containerName);
  }
  return container;
}

app.http('status', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'status',
  handler: async (request, context) => {
    let cosmos = { connected: false };
    try {
      const c = getContainer();
      if (c) {
        await c.items.query('SELECT VALUE COUNT(1) FROM c').fetchAll();
        cosmos = { connected: true, database: databaseName, container: containerName };
      }
    } catch (err) {
      context.error('Cosmos check failed', err);
      cosmos = { connected: false, error: err.message };
    }

    return {
      jsonBody: {
        runtime: 'node',
        version: process.version,
        timestamp: new Date().toISOString(),
        cosmos
      }
    };
  }
});
