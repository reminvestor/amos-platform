# /add-integration Command

Set up a new external API integration for AMOS.

## Usage

```
/add-integration [service name]
```

## What This Command Does

Delegates to the **integration-connector** agent to:
1. Ask about the service and authentication
2. Create Integration and IntegrationOperation records
3. Implement API handlers if needed
4. Test with real API credentials

## Example

```
/add-integration Shopify
```

## Agent Task

Use the Task tool with subagent_type: "integration-connector"
