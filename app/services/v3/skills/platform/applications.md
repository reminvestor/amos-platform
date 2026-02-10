# Applications & Custom Modules

## Overview
Applications (or modules) are custom data-driven apps built on the platform. They extend the core CRM with domain-specific functionality — inventory tracking, project management, order systems, etc.

## Key Concepts
- **AppModule**: The application definition (schema, views, logic)
- **CustomObject**: Data records within the app (like rows in a database)
- **Schema**: Field definitions for the custom object
- **Views**: How the data is displayed (list, detail, forms)

## Database Models
- `AppModule` — The application container
- `CustomObjectDefinition` — Schema for the custom objects
- `CustomObject` — Actual data records

## Canvases
- `app_designer` — Visual builder for creating/editing applications
- `module_manager` — List and manage all custom modules

## Key Fields for AppModule
- `name`: Module name (e.g., "Inventory Tracker")
- `slug`: URL-friendly identifier
- `status`: draft, active, archived
- `schema`: JSON defining fields and types

## Schema Field Types
- `text` — Single line text
- `textarea` — Multi-line text
- `number` — Integer or decimal
- `currency` — Money with currency code
- `date` — Date picker
- `datetime` — Date + time
- `select` — Dropdown options
- `multi_select` — Multiple selections
- `boolean` — Yes/no toggle
- `reference` — Link to another object (contact, opportunity, etc.)
- `file` — File attachment
- `json` — Structured data

## Common Operations

### Query custom apps
Use the platform_query tool with type: "app_modules", filters: { status: "active" }

### Create an application
Use the platform_create tool with type: "app_module" and data containing:
- name: "Project Tracker"
- slug: "project-tracker"
- schema: { fields: [{ name: "project_name", type: "text", required: true }, { name: "status", type: "select", options: ["planning", "active", "complete"] }, { name: "due_date", type: "date" }, { name: "owner", type: "reference", reference_type: "contact" }, { name: "budget", type: "currency" }] }

### Open app designer
Use the load_canvas tool with canvas_name: "app_designer"
Or with canvas_name: "app_designer", canvas_data: { app_module_id: 42 }

### Create a record in a custom app
Use the platform_create tool with type: "custom_object" and data: { app_module_id: 42, data: { project_name: "Website Redesign", status: "planning", due_date: "2026-03-15", budget: 5000 } }

### Query records from a custom app
Use the platform_query tool with type: "custom_objects", filters: { app_module_id: 42, "data.status": "active" }

## Design Patterns

### Simple CRUD App
1. Define schema with fields
2. Platform auto-generates list and detail views
3. Users can add/edit/delete records

### Relational App
1. Create multiple object types
2. Use `reference` fields to link them
3. Example: Projects → Tasks → Time Entries

### Integration-Connected App
1. Define schema matching external data
2. Create workflow to sync on schedule
3. Use integration actions to push/pull data

## Tips
- Start with the data model — what fields do you need?
- Use meaningful field names — they become column headers
- Add required fields sparingly — flexibility is valuable
- Reference fields create powerful relationships
- Status fields + workflows = automated state machines
