#!/bin/bash

echo "🔧 Resetting Swift Package dependencies..."

# Remove Package.resolved to force fresh resolution
if [ -f "Package.resolved" ]; then
    echo "Removing Package.resolved..."
    rm Package.resolved
fi

# Remove Xcode's package cache for this project
echo "Clearing Xcode DerivedData for this project..."
rm -rf ~/Library/Developer/Xcode/DerivedData/WalkWrite-*

echo "✅ Package cache cleared!"
echo ""
echo "Next steps:"
echo "1. Open WalkWrite.xcodeproj in Xcode"
echo "2. Wait for 'Resolving Package Dependencies' to complete"
echo "3. If packages fail to resolve:"
echo "   - File → Packages → Reset Package Caches"
echo "   - File → Packages → Update to Latest Package Versions"
echo ""
echo "Note: Initial package resolution may take 5-10 minutes as Xcode"
echo "downloads and builds the MLX dependencies."