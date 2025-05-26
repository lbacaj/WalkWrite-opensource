#!/bin/bash

echo "🔧 Setting up WalkWrite for your development environment..."
echo ""

# Check if Config.xcconfig exists
if [ ! -f "Config.xcconfig" ]; then
    echo "Creating Config.xcconfig from template..."
    cp Config.xcconfig.template Config.xcconfig
    echo "✅ Config.xcconfig created"
    echo ""
fi

# Get current values from Config.xcconfig
CURRENT_TEAM=$(grep "DEVELOPMENT_TEAM" Config.xcconfig | cut -d'=' -f2 | xargs)
CURRENT_PREFIX=$(grep "PRODUCT_BUNDLE_IDENTIFIER_PREFIX" Config.xcconfig | cut -d'=' -f2 | xargs)

echo "Current configuration:"
echo "  Development Team: ${CURRENT_TEAM:-"(not set)"}"
echo "  Bundle ID Prefix: ${CURRENT_PREFIX:-"(not set)"}"
echo ""

# Ask for development team
echo "Enter your Apple Development Team ID (leave empty for personal development):"
read -p "> " TEAM_ID

# Ask for bundle identifier prefix
echo ""
echo "Enter your bundle identifier prefix (e.g., com.yourcompany):"
read -p "> " BUNDLE_PREFIX

# Update Config.xcconfig
if [ -n "$TEAM_ID" ]; then
    sed -i '' "s/DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = $TEAM_ID/" Config.xcconfig
else
    sed -i '' "s/DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = /" Config.xcconfig
fi

if [ -n "$BUNDLE_PREFIX" ]; then
    sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER_PREFIX = .*/PRODUCT_BUNDLE_IDENTIFIER_PREFIX = $BUNDLE_PREFIX/" Config.xcconfig
fi

echo ""
echo "✅ Configuration updated!"
echo ""
echo "Next steps:"
echo "1. Open WalkWrite.xcodeproj in Xcode"
echo "2. Select your development team in the project settings if needed"
echo "3. The app bundle ID will be: ${BUNDLE_PREFIX:-com.example}.walkwrite"
echo ""
echo "Note: You may need to change the bundle ID in Xcode if it conflicts"
echo "with an existing app on your developer account."