# /add-integration Command

Set up a new external API integration for AMOS.

## Usage

```
/add-integration [service name]
```

## What This Command Does

Uses the **starting-features** skill to:
1. Help you design the integration structure
2. Create Integration and IntegrationOperation records
3. Implement authentication handlers (OAuth, API key, etc.)
4. Set up API request/response transformations
5. Create connection management UI

## Examples

```
/add-integration Shopify
```

```
/add-integration Twilio for SMS notifications
```

## Integration Components

Creates the following:
- **Integration model** - Service definition (name, auth_type, base_url)
- **IntegrationOperation records** - API endpoint definitions
- **IntegrationApiService handlers** - Request/response logic
- **Connection UI** - User credential management
- **Integration tools** - Scout AI tool wrappers (optional)

## Implementation

This command uses the starting-features skill which:
- Follows AMOS integration patterns
- Sets up proper authentication flows
- Creates operation definitions for API endpoints
- Provides testing guidance with real credentials

## Next Steps

After running this command:
1. Test operations with `list_operations` and `invoke_operation` tools
2. Verify connection health checks work
3. Test integration in Scout AI workflows
4. Run tests with `running-tests` skill
5. Use `/quick-commit` to commit your changes

## Uses Skills

- **starting-features** - Integration scaffolding and implementation guidance
