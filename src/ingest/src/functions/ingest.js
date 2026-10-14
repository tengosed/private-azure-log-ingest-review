const { randomUUID } = require('crypto');
const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

// Table keys may not contain / \ # ? or control characters, and are capped at 1 KiB.
const KEY_PATTERN = /^[^/\\#?\u0000-\u001f\u007f-\u009f]{1,255}$/;
const MAX_MESSAGE_LENGTH = 32000;

let tableClient;
function getClient() {
  if (!tableClient) {
    const account = process.env.TABLE_STORAGE_ACCOUNT_NAME;
    const table = process.env.TABLE_NAME || 'applogs';
    const credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID
    });
    tableClient = new TableClient(`https://${account}.table.core.windows.net`, table, credential);
  }
  return tableClient;
}

app.http('ingest', {
  methods: ['POST'],
  // Callers must send the function key (x-functions-key); the network layer also restricts source IPs.
  authLevel: 'function',
  route: 'ingest',
  handler: async (request, context) => {
    if (!process.env.TABLE_STORAGE_ACCOUNT_NAME) {
      return { status: 500, jsonBody: { error: 'TABLE_STORAGE_ACCOUNT_NAME is not configured.' } };
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return { status: 400, jsonBody: { error: 'Body must be valid JSON.' } };
    }

    const { message, partitionKey = 'General', rowKey = randomUUID(), severity = 'Information' } = body ?? {};

    if (typeof message !== 'string' || message.length === 0 || message.length > MAX_MESSAGE_LENGTH) {
      return { status: 400, jsonBody: { error: `'message' is required and must be a string up to ${MAX_MESSAGE_LENGTH} characters.` } };
    }
    if (typeof severity !== 'string' || severity.length === 0 || severity.length > 64) {
      return { status: 400, jsonBody: { error: "'severity' must be a string up to 64 characters." } };
    }
    if (![partitionKey, rowKey].every((k) => typeof k === 'string' && KEY_PATTERN.test(k))) {
      return { status: 400, jsonBody: { error: "'partitionKey' and 'rowKey' must be strings without / \\ # ? or control characters." } };
    }

    try {
      await getClient().createEntity({
        partitionKey,
        rowKey,
        Message: message,
        Severity: severity
      });
      return {
        status: 201,
        jsonBody: { status: 'Success', partitionKey, rowKey }
      };
    } catch (err) {
      if (err.statusCode === 409) {
        return { status: 409, jsonBody: { error: 'An entity with this partitionKey and rowKey already exists.' } };
      }
      context.error('Error writing log entity:', err);
      return { status: 500, jsonBody: { error: 'Failed to write log entry.' } };
    }
  }
});
