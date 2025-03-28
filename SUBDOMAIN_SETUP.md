# Subdomain Setup for Development

This application uses subdomains to separate the marketing site from the actual application interface. Below are instructions on how to access these correctly during development.

## Accessing the Application in Development

### Option 1: Using localhost

To access the application with subdomains on localhost, you can use:

- Marketing site: http://localhost:3000
- Application (Nuvola Networks entity): http://nuvola.localhost:3000

Note: Some browsers may have issues with `.localhost` subdomains. If you experience problems, try Option 2 below.

### Option 2: Using lvh.me (recommended)

`lvh.me` is a domain that resolves to `127.0.0.1` (your local machine) and allows for subdomains, making it perfect for testing:

- Marketing site: http://lvh.me:3000
- Application (Nuvola Networks entity): http://nuvola.lvh.me:3000

### Option 3: Updating your hosts file

If neither of the above options works, you can modify your hosts file:

1. Edit your hosts file:
   - On macOS/Linux: `/etc/hosts`
   - On Windows: `C:\Windows\System32\drivers\etc\hosts`

2. Add these lines:
   ```
   127.0.0.1 yourdomain.test
   127.0.0.1 nuvola.yourdomain.test
   ```

3. Access the application at:
   - Marketing site: http://yourdomain.test:3000
   - Application: http://nuvola.yourdomain.test:3000

## Notes on Subdomain Handling

- The application is configured to show the marketing site when no subdomain is present
- When using a subdomain (e.g., `nuvola.lvh.me`), the application interface is shown
- Entity-specific data is only accessible when using the appropriate subdomain

## Troubleshooting

If you see a "Blocked Host" error:

1. Make sure you're using the correct URL format
2. Check that the subdomain is properly configured in `config/environments/development.rb`
3. Restart your Rails server after making configuration changes 