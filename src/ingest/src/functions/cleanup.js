const { app } = require('@azure/functions');
const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

const BATCH_SIZE = 100; // Table transactions allow 100 operations on a single partition

app.timer('cleanup', {
  // Daily at 02:00 UTC (NCRONTAB: second minute hour day month day-of-week)
  schedule: '0 0 2 * * *',
  runOnStartup: false,
  handler: async (_timer, context) => {
    const account = process.env.TABLE_STORAGE_ACCOUNT_NAME;
    const retentionDays = Number(process.env.RETENTION_DAYS || 30);
    if (!account || !Number.isFinite(retentionDays) || retentionDays < 1) {
      throw new Error('TABLE_STORAGE_ACCOUNT_NAME and a RETENTION_DAYS value >= 1 are required.');
    }

    const client = new TableClient(
      `https://${account}.table.core.windows.net`,
      process.env.TABLE_NAME || 'applogs',
      new DefaultAzureCredential({ managedIdentityClientId: process.env.AZURE_CLIENT_ID })
    );

    const cutoff = new Date(Date.now() - retentionDays * 86400000).toISOString();
    const byPartition = new Map();
    const entities = client.listEntities({
      queryOptions: { filter: `Timestamp lt datetime'${cutoff}'`, select: ['PartitionKey', 'RowKey'] }
    });
    for await (const e of entities) {
      if (!byPartition.has(e.partitionKey)) byPartition.set(e.partitionKey, []);
      byPartition.get(e.partitionKey).push(e.rowKey);
    }

    let deleted = 0;
    for (const [partitionKey, rowKeys] of byPartition) {
      for (let i = 0; i < rowKeys.length; i += BATCH_SIZE) {
        const actions = rowKeys.slice(i, i + BATCH_SIZE).map((rk) => ['delete', { partitionKey, rowKey: rk }]);
        await client.submitTransaction(actions);
        deleted += actions.length;
      }
    }
    context.log(`Cleanup removed ${deleted} record(s) older than ${retentionDays} day(s) (before ${cutoff}).`);
  }
});
