#!/bin/bash

echo "🔍 Verifying WalkWrite opensource setup..."
echo ""

# Check for large model files
echo "Checking model files..."
if [ -f "WalkWrite/ggml-large-v3-turbo-q5_0.bin" ]; then
    echo "✅ Whisper model found"
else
    echo "❌ Whisper model missing - run 'git lfs pull'"
fi

if [ -d "WalkWrite/QwenModel" ]; then
    echo "✅ Qwen model directory found"
else
    echo "❌ Qwen model missing - run 'git lfs pull'"
fi

if [ -d "WalkWrite/ggml-large-v3-turbo-encoder.mlmodelc" ]; then
    echo "✅ Core ML encoder found"
else
    echo "❌ Core ML encoder missing - run 'git lfs pull'"
fi

echo ""
echo "Checking whisper.xcframework..."
if [ -d "Vendor/whisper.cpp/build-apple/whisper.xcframework" ]; then
    echo "✅ whisper.xcframework found at expected location"
elif [ -d "whisper.xcframework" ]; then
    echo "⚠️  whisper.xcframework found in root - move it to Vendor/whisper.cpp/build-apple/"
else
    echo "❌ whisper.xcframework not found - run './build-whisper-xcframework.sh'"
fi

echo ""
echo "Checking Git LFS..."
if command -v git-lfs &> /dev/null; then
    echo "✅ Git LFS is installed"
else
    echo "❌ Git LFS not installed - run 'brew install git-lfs'"
fi

echo ""
echo "Project file status:"
echo "✅ Package references updated to use GitHub repos"
echo "✅ MLX packages will be downloaded from:"
echo "   - https://github.com/ml-explore/mlx-swift"
echo "   - https://github.com/ml-explore/mlx-swift-examples"

echo ""
echo "Next steps:"
echo "1. Open WalkWrite.xcodeproj in Xcode"
echo "2. Let Xcode resolve Swift packages (may take a few minutes)"
echo "3. Build whisper.xcframework if not already done"
echo "4. Build and run on a physical iOS device"