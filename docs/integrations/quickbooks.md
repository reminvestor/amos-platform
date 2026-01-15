# QuickBooks Online Integration Expert Knowledge

## Overview
QuickBooks Online (QBO) is cloud-based accounting software by Intuit. This document contains expert knowledge for interacting with the QuickBooks API.

## Authentication
- **Type**: OAuth 2.0
- **Token URL**: https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer
- **Scopes**: com.intuit.quickbooks.accounting
- **Important**: Tokens must be refreshed before expiry. QuickBooks uses the `realmId` (company ID) in all API paths.

## API Base URLs
- **Sandbox**: https://sandbox-quickbooks.api.intuit.com/v3
- **Production**: https://quickbooks.api.intuit.com/v3

## QuickBooks Query Language (QBL)

**CRITICAL**: QuickBooks uses a SQL-like query language for retrieving data. Unlike REST APIs that use query parameters, many QuickBooks read operations use a `/query` endpoint with a `query` parameter containing SQL-like syntax.

### Query Syntax
```sql
SELECT * FROM EntityName WHERE condition ORDERBY field STARTPOSITION n MAXRESULTS m
```

### Supported Entities (case-sensitive)
- Invoice, Customer, Item, Account, Payment
- Vendor, Bill, PurchaseOrder, Estimate
- Employee, Class, Department, TaxCode

### Common Query Examples

**List All Invoices**:
```
query: "SELECT * FROM Invoice"
```

**Open Invoices (unpaid)**:
```
query: "SELECT * FROM Invoice WHERE Balance > '0'"
```

**Paid Invoices**:
```
query: "SELECT * FROM Invoice WHERE Balance = '0'"
```

**Invoices for a specific customer**:
```
query: "SELECT * FROM Invoice WHERE CustomerRef = '123'"
```

**Recent Invoices (last 30 days)**:
```
query: "SELECT * FROM Invoice WHERE TxnDate >= '2024-01-01'"
```

**Overdue Invoices**:
```
query: "SELECT * FROM Invoice WHERE Balance > '0' AND DueDate < '2024-01-15'"
```

**List All Customers**:
```
query: "SELECT * FROM Customer"
```

**Active Customers Only**:
```
query: "SELECT * FROM Customer WHERE Active = true"
```

**Customers by Name**:
```
query: "SELECT * FROM Customer WHERE DisplayName LIKE '%Smith%'"
```

**Paginated Results**:
```
query: "SELECT * FROM Invoice STARTPOSITION 1 MAXRESULTS 50"
```

## Date and Time Formats
- **Date format**: YYYY-MM-DD (e.g., '2024-01-15')
- **DateTime format**: YYYY-MM-DDTHH:MM:SS (e.g., '2024-01-15T14:30:00')
- **Timezone**: All dates are in the company's timezone

## Entity Relationships

### Invoice Structure
```json
{
  "CustomerRef": {"value": "customer_id"},
  "Line": [
    {
      "Amount": 100.00,
      "DetailType": "SalesItemLineDetail",
      "SalesItemLineDetail": {
        "ItemRef": {"value": "item_id"}
      }
    }
  ],
  "DueDate": "2024-02-15",
  "DocNumber": "1001"
}
```

### Payment Structure (linked to Invoice)
```json
{
  "CustomerRef": {"value": "customer_id"},
  "TotalAmt": 100.00,
  "Line": [
    {
      "Amount": 100.00,
      "LinkedTxn": [
        {"TxnId": "invoice_id", "TxnType": "Invoice"}
      ]
    }
  ]
}
```

## Common Errors and Solutions

### "System Failure Error: {0}"
**Cause**: Usually malformed query syntax or wrong parameter format.
**Solution**: Ensure query parameter is properly formatted SQL-like string. Use single quotes for values.

### "Invalid Reference Id"
**Cause**: Referenced entity (Customer, Item) doesn't exist.
**Solution**: First query to get valid IDs before creating invoices/payments.

### "Business Validation Error"
**Cause**: Required fields missing or invalid data.
**Solution**: Check required fields: CustomerRef is mandatory for invoices.

### Rate Limit Errors
**Limits**: 500 requests per minute, 10 concurrent connections
**Solution**: Implement exponential backoff, batch operations when possible.

## Best Practices

### For Listing Data
1. Always use the `/query` endpoint with proper SQL-like syntax
2. Use MAXRESULTS to limit response size (default: 100, max: 1000)
3. Use STARTPOSITION for pagination
4. Filter early - use WHERE clauses instead of fetching all and filtering client-side

### For Creating Records
1. Fetch valid CustomerRef IDs first
2. Fetch valid ItemRef IDs for line items
3. Use sync token for updates (read-before-write)
4. Handle sparse updates (send only changed fields)

### Status Filtering
QuickBooks doesn't have a "status" field on invoices. Instead:
- **Open/Unpaid**: WHERE Balance > '0'
- **Paid**: WHERE Balance = '0'
- **Overdue**: WHERE Balance > '0' AND DueDate < 'current_date'

## Parameter Mapping Reference

When Amos or users request common operations, translate to QuickBooks Query Language:

| User Request | QuickBooks Query |
|-------------|------------------|
| "Open invoices" | SELECT * FROM Invoice WHERE Balance > '0' |
| "Paid invoices" | SELECT * FROM Invoice WHERE Balance = '0' |
| "All customers" | SELECT * FROM Customer |
| "Active customers" | SELECT * FROM Customer WHERE Active = true |
| "Recent invoices" | SELECT * FROM Invoice WHERE TxnDate >= '{30_days_ago}' |
| "Limit to 50" | Add MAXRESULTS 50 to query |
| "Page 2" | Use STARTPOSITION 51 MAXRESULTS 50 |

## Integration Operations Available

### list_invoices (quickbooks.list_invoices)
- Path: /company/{companyId}/query
- Method: GET
- Required param: `query` (SQL-like string)
- Example: `query: "SELECT * FROM Invoice WHERE Balance > '0' MAXRESULTS 50"`

### list_customers (quickbooks.list_customers.v3)
- Path: /company/{companyId}/query
- Method: GET
- Required param: `query` (SQL-like string)
- Example: `query: "SELECT * FROM Customer MAXRESULTS 100"`

### create_invoice (quickbooks.create_invoice.v3)
- Path: /company/{companyId}/invoice
- Method: POST
- Required body: CustomerRef, Line items

### create_payment (quickbooks.create_payment.v3)
- Path: /company/{companyId}/payment
- Method: POST
- Required body: CustomerRef, TotalAmt

### get_company_info (quickbooks.get_company_info.v3)
- Path: /company/{companyId}/companyinfo/{companyId}
- Method: GET
- No parameters required

## Troubleshooting Checklist

1. ✅ Is the OAuth token valid and not expired?
2. ✅ Is the realmId (company ID) included in the path?
3. ✅ For queries, is the `query` parameter a properly formatted SQL-like string?
4. ✅ Are values in single quotes in the query?
5. ✅ Is the entity name properly cased (Invoice, not invoice)?
6. ✅ For creating records, do all referenced IDs exist?

---
*This documentation is maintained for use by the QuickBooks integration agent and Amos orchestrator. Last updated: January 2026.*

