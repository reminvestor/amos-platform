# Script to update QuickBooks OAuth redirect URI for local development
# Run with: rails runner lib/scripts/update_qbo_redirect_local.rb

oauth_config = OauthConfiguration.joins(:integration).find_by(integrations: { slug: 'quickbooks' })

if oauth_config
  old_uri = oauth_config.redirect_uri
  oauth_config.update!(redirect_uri: 'http://app.localhost:5001/integrations/callback/quickbooks')
  puts "✅ Updated QuickBooks redirect URI"
  puts "   Old: #{old_uri}"
  puts "   New: #{oauth_config.redirect_uri}"
  puts ""
  puts "🔧 Don't forget to update this in your QuickBooks app at:"
  puts "   https://developer.intuit.com/app/developer/myapps"
else
  puts "❌ QuickBooks OAuth configuration not found"
end

