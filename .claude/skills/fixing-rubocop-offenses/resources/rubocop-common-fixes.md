# RuboCop Common Fixes Reference

Quick reference for common RuboCop offenses and how to fix them.

## Auto-Fixable Offenses

These can be fixed automatically with `rubocop -a` or `rubocop -A`:

### Style/StringLiterals
**Problem:** Inconsistent quote usage
```ruby
# Bad
name = "John"

# Good
name = 'John'  # Use single quotes unless interpolation needed
age = "#{years} old"  # Double quotes for interpolation
```

### Layout/TrailingWhitespace
**Problem:** Whitespace at end of lines
- Run `rubocop -a` to auto-fix
- Configure editor to trim trailing whitespace on save

### Style/HashSyntax
**Problem:** Old-style hash syntax
```ruby
# Bad
{ :name => 'John', :age => 30 }

# Good
{ name: 'John', age: 30 }
```

### Layout/EmptyLineAfterGuardClause
**Problem:** Missing empty line after guard clause
```ruby
# Bad
return unless user
user.update(params)

# Good
return unless user

user.update(params)
```

### Style/FrozenStringLiteralComment
**Problem:** Missing frozen string literal comment
```ruby
# Good - Add to top of file
# frozen_string_literal: true

class MyClass
  # ...
end
```

## Manual Fixes Required

### Metrics/MethodLength
**Problem:** Method too long (>10 lines default)

**Solutions:**
```ruby
# Bad - 20 line method
def process_campaign
  # ... lots of code
end

# Good - Extract smaller methods
def process_campaign
  validate_campaign
  prepare_recipients
  send_emails
end

def validate_campaign
  # ...
end
```

### Metrics/AbcSize
**Problem:** Method complexity too high (Assignment, Branch, Condition)

**Solutions:**
- Extract sub-methods
- Move logic to service classes
- Simplify conditional logic

### Metrics/CyclomaticComplexity
**Problem:** Too many branches (if/case statements)

**Solutions:**
```ruby
# Bad
def status_color
  if status == 'draft'
    'gray'
  elsif status == 'active'
    'green'
  elsif status == 'paused'
    'yellow'
  elsif status == 'completed'
    'blue'
  end
end

# Good - Use hash lookup
STATUS_COLORS = {
  'draft' => 'gray',
  'active' => 'green',
  'paused' => 'yellow',
  'completed' => 'blue'
}.freeze

def status_color
  STATUS_COLORS[status] || 'gray'
end
```

### Style/Documentation
**Problem:** Missing class/module documentation

**Solutions:**
```ruby
# Bad
class Campaign
  # ...
end

# Good
# Represents an email campaign with scheduling and tracking
class Campaign < ApplicationRecord
  # ...
end
```

### Naming/VariableName
**Problem:** Variable name doesn't follow conventions

**Solutions:**
- Use `snake_case` for variables and methods
- Use `SCREAMING_SNAKE_CASE` for constants
- Use `CamelCase` for classes/modules

## Rails-Specific

### Rails/HasManyOrHasOneDependent
**Problem:** Missing dependent option on associations

```ruby
# Bad
has_many :contacts

# Good
has_many :contacts, dependent: :destroy  # Delete associated records
has_many :contacts, dependent: :nullify  # Set foreign key to null
has_many :contacts, dependent: :restrict_with_error  # Prevent deletion
```

### Rails/I18nLocaleTexts
**Problem:** Hardcoded text instead of I18n

```ruby
# Bad
flash[:notice] = "Campaign created successfully"

# Good
flash[:notice] = t('campaigns.created')
# Or if I18n not used in project, disable cop in .rubocop.yml
```

### Rails/UnknownEnv
**Problem:** Non-standard environment

```ruby
# Bad
if Rails.env.staging?

# Good - Define in config/environments/staging.rb
# Or use:
if Rails.env.production? || Rails.env.staging?
```

## Project-Specific Disables

Add to `.rubocop.yml` if certain cops don't fit project style:

```yaml
# Disable cops that don't fit project
Style/Documentation:
  Enabled: false  # If not documenting all classes

Metrics/MethodLength:
  Max: 15  # Increase limit if needed

Metrics/BlockLength:
  Exclude:
    - 'config/**/*'  # Config files often have long blocks
    - 'test/**/*'    # Test files often have long test blocks

Rails/I18nLocaleTexts:
  Enabled: false  # If not using I18n
```

## Common Patterns

### Inline Disables
For rare exceptions:
```ruby
def complex_method
  # rubocop:disable Metrics/MethodLength
  # ... necessarily long method
  # rubocop:enable Metrics/MethodLength
end
```

### File-Level Disables
```ruby
# rubocop:disable Rails/Output
# (Useful for rake tasks that need puts/print)
```

## Checking Specific Files

```bash
# Check single file
rubocop app/models/campaign.rb

# Auto-fix single file
rubocop -a app/models/campaign.rb

# Check only certain cops
rubocop --only Style/StringLiterals

# Generate TODO list for existing offenses
rubocop --auto-gen-config
```

## Configuration Tips

In `.rubocop.yml`:

```yaml
# Inherit from RuboCop defaults
inherit_from: .rubocop_todo.yml

# Set Ruby and Rails versions
AllCops:
  TargetRubyVersion: 3.2
  TargetRailsVersion: 8.0
  NewCops: enable
  Exclude:
    - 'db/schema.rb'
    - 'node_modules/**/*'
    - 'vendor/**/*'

# Customize limits
Metrics/MethodLength:
  Max: 15
  Exclude:
    - 'test/**/*'

Metrics/ClassLength:
  Max: 150

Layout/LineLength:
  Max: 120
```

## Quick Reference

| Offense | Quick Fix |
|---------|-----------|
| Trailing whitespace | `rubocop -a` |
| String literals | Use single quotes |
| Hash syntax | Use new syntax `key: value` |
| Missing frozen string | Add `# frozen_string_literal: true` |
| Method too long | Extract methods |
| ABC size high | Extract to service class |
| Missing dependent | Add `dependent: :destroy` |
| Hardcoded text | Use I18n or disable cop |

## Resources

- [RuboCop Docs](https://docs.rubocop.org/)
- [RuboCop Rails](https://docs.rubocop.org/rubocop-rails/)
- Project `.rubocop.yml` for custom rules
