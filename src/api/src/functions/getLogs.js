const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

app.http('getLogs', {
  methods: ['GET'],
  // The SWA linked-backend integration protects the public Function origin.
  authLevel: 'anonymous',
  route: 'logs',
  handler: async (request, context) => {
    context.log('HTTP trigger function processing request to fetch logs.');

    const storageAccountName = process.env.TABLE_STORAGE_ACCOUNT_NAME;
    const tableName = process.env.TABLE_NAME || 'applogs';
    const clientId = process.env.AZURE_CLIENT_ID;

    if (!storageAccountName) {
      return {
        status: 500,
        jsonBody: { error: 'TABLE_STORAGE_ACCOUNT_NAME environment variable is not configured.' }
      };
    }

    try {
      const tableUrl = `https://${storageAccountName}.table.core.windows.net`;
      
      // Authenticate using User-Assigned Managed Identity (configured via AZURE_CLIENT_ID)
      const credential = new DefaultAzureCredential({
        managedIdentityClientId: clientId
      });

      const client = new TableClient(tableUrl, tableName, credential);

      const logs = [];
      const entities = client.listEntities();

      for await (const entity of entities) {
        logs.push({
          partitionKey: entity.partitionKey,
          rowKey: entity.rowKey,
          message: entity.Message,
          severity: entity.Severity,
          timestamp: entity.timestamp
        });
      }

      return {
        status: 200,
        headers: {
          'Content-Type': 'application/json'
        },
        jsonBody: {
          count: logs.length,
          logs: logs
        }
      };
    } catch (err) {
      context.error('Error fetching table logs:', err);
      return {
        status: 500,
        jsonBody: {
          error: 'Failed to retrieve logs from Table Storage',
          details: err.message
        }
      };
    }
  }
});
