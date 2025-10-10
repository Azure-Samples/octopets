using Octopets.Backend.Models;
using Octopets.Backend.Repositories.Interfaces;

namespace Octopets.Backend.Endpoints;

public static class ListingEndpoints
{    // Memory-safe operation with bounded allocations and proper resource management
    private static async Task AReallyExpensiveOperation(ILogger logger, CancellationToken cancellationToken = default)
    {
        // Add telemetry for monitoring
        var startTime = DateTime.UtcNow;
        
        try
        {
            // Use a bounded allocation instead of unbounded 1GB
            // This simulates work without causing OOM
            const int maxIterations = 10;
            const int smallBufferSize = 1024; // 1KB instead of 100MB
            
            var bufferPool = System.Buffers.ArrayPool<byte>.Shared;
            
            for (int i = 0; i < maxIterations; i++)
            {
                // Check for cancellation
                cancellationToken.ThrowIfCancellationRequested();
                
                // Use pooled buffer to avoid GC pressure
                byte[] buffer = bufferPool.Rent(smallBufferSize);
                try
                {
                    // Simulate some work without holding memory
                    // Only fill the requested size, not the entire rented buffer
                    Array.Fill(buffer, (byte)(i % 256), 0, smallBufferSize);
                    
                    // Small delay to simulate work
                    await Task.Delay(10, cancellationToken);
                }
                finally
                {
                    // Return buffer to pool
                    bufferPool.Return(buffer);
                }
            }
        }
        finally
        {
            // Add telemetry
            var duration = DateTime.UtcNow - startTime;
            logger.LogInformation("AReallyExpensiveOperation completed in {DurationMs}ms", duration.TotalMilliseconds);
        }
    }

    public static void MapListingEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/listings")
                       .WithTags("Listings");

        // GET all listings
        group.MapGet("/", async (IListingRepository repository) =>
        {
            var listings = await repository.GetAllAsync();
            return Results.Ok(listings);
        })
        .WithName("GetAllListings")
        .WithDescription("Gets all listings")
        .WithOpenApi();        // GET listing by id
        group.MapGet("/{id:int}", async (int id, IListingRepository repository, IConfiguration config, ILogger<Program> logger, CancellationToken cancellationToken) =>
        {
            // Only throw exception or simulate memory issues if ERRORS flag is set to true
            if (config.GetValue<bool>("ERRORS"))
            {
                await AReallyExpensiveOperation(logger, cancellationToken);
            }

            var listing = await repository.GetByIdAsync(id);
            return listing is null ? Results.NotFound() : Results.Ok(listing);
        })
        .WithName("GetListingById")
        .WithDescription("Gets a listing by its ID")
        .WithOpenApi(operation =>
        {
            operation.Parameters[0].Description = "The ID of the listing";
            return operation;
        });        // POST new listing
        group.MapPost("/", async (Listing listing, IListingRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var newListing = await repository.CreateAsync(listing);
            return Results.Created($"/api/listings/{newListing.Id}", newListing);
        })
        .WithName("CreateListing")
        .WithDescription("Creates a new listing")
        .WithOpenApi();

        // PUT update listing
        group.MapPut("/{id:int}", async (int id, Listing listing, IListingRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var updatedListing = await repository.UpdateAsync(id, listing);
            return updatedListing is null ? Results.NotFound() : Results.Ok(updatedListing);
        })
        .WithName("UpdateListing")
        .WithDescription("Updates an existing listing")
        .WithOpenApi();

        // DELETE listing
        group.MapDelete("/{id:int}", async (int id, IListingRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var result = await repository.DeleteAsync(id);
            return result ? Results.NoContent() : Results.NotFound();
        })
        .WithName("DeleteListing")
        .WithDescription("Deletes a listing")
        .WithOpenApi();
    }
}
