using Azure.Identity;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Api.Dotnet;

public class StatusFunction
{
    private static readonly string? Endpoint = Environment.GetEnvironmentVariable("COSMOS_ENDPOINT");
    private static readonly string Database = Environment.GetEnvironmentVariable("COSMOS_DATABASE") ?? "app";
    private static readonly string Container = Environment.GetEnvironmentVariable("COSMOS_CONTAINER") ?? "items";

    private static CosmosClient? _client;
    private static CosmosClient? GetClient() =>
        Endpoint is null
            ? null
            : _client ??= new CosmosClient(Endpoint, new DefaultAzureCredential());

    private readonly ILogger<StatusFunction> _logger;
    public StatusFunction(ILogger<StatusFunction> logger) => _logger = logger;

    [Function("status")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "status")] HttpRequest req)
    {
        object cosmos = new { connected = false };
        try
        {
            var client = GetClient();
            if (client is not null)
            {
                var container = client.GetContainer(Database, Container);
                var iterator = container.GetItemQueryIterator<int>("SELECT VALUE COUNT(1) FROM c");
                if (iterator.HasMoreResults) await iterator.ReadNextAsync();
                cosmos = new { connected = true, database = Database, container = Container };
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Cosmos check failed");
            cosmos = new { connected = false, error = ex.Message };
        }

        return new OkObjectResult(new
        {
            runtime = "dotnet",
            version = Environment.Version.ToString(),
            timestamp = DateTime.UtcNow.ToString("o"),
            cosmos
        });
    }
}
