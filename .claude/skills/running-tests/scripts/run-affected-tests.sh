#!/bin/bash
# Run only tests affected by git changes

set -e

echo "🔍 Finding affected tests based on git changes..."
echo ""

# Get changed files
CHANGED_FILES=$(git diff --name-only main...HEAD 2>/dev/null || git diff --name-only HEAD~1)

if [ -z "$CHANGED_FILES" ]; then
  echo "⚠️  No changes detected. Running all tests..."
  docker-compose run --rm web rails test
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"
echo ""

# Map changed files to test files
TEST_FILES=""

echo "$CHANGED_FILES" | while read file; do
  case "$file" in
    app/models/*.rb)
      model_name=$(basename "$file" .rb)
      test_file="test/models/${model_name}_test.rb"
      [ -f "$test_file" ] && echo "$test_file"
      ;;
    app/controllers/*.rb)
      controller_name=$(basename "$file" .rb)
      test_file="test/controllers/${controller_name}_test.rb"
      [ -f "$test_file" ] && echo "$test_file"
      ;;
    app/services/*.rb)
      service_name=$(basename "$file" .rb)
      test_file="test/services/${service_name}_test.rb"
      [ -f "$test_file" ] && echo "$test_file"
      ;;
    app/services/tools/*.rb)
      tool_name=$(basename "$file" .rb)
      test_file="test/services/tools/${tool_name}_test.rb"
      [ -f "$test_file" ] && echo "$test_file"
      ;;
    *)
      ;;
  esac
done > /tmp/affected_tests.txt

AFFECTED=$(cat /tmp/affected_tests.txt | sort | uniq)

if [ -z "$AFFECTED" ]; then
  echo "⚠️  No matching test files found. Running all tests..."
  docker-compose run --rm web rails test
else
  echo "🎯 Running affected tests:"
  echo "$AFFECTED"
  echo ""

  # Run each test file
  echo "$AFFECTED" | while read test_file; do
    echo "Running: $test_file"
    docker-compose run --rm web rails test "$test_file"
  done
fi

rm -f /tmp/affected_tests.txt

echo ""
echo "✅ Affected tests complete!"
