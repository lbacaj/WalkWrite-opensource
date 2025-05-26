#!/bin/bash

# Build script for whisper.cpp XCFramework
# This creates a universal framework that works on iOS devices and simulators

set -e

echo "Building whisper.cpp XCFramework..."

# Clone whisper.cpp if it doesn't exist
if [ ! -d "whisper.cpp" ]; then
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git
fi

cd whisper.cpp

# Clean previous builds
rm -rf build-ios-device build-ios-sim build-xcframework

# Build for iOS device
echo "Building for iOS device..."
cmake -B build-ios-device \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DWHISPER_COREML=ON \
    -DWHISPER_COREML_ALLOW_FALLBACK=ON

cmake --build build-ios-device --config Release

# Build for iOS simulator
echo "Building for iOS simulator..."
cmake -B build-ios-sim \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=OFF \
    -DWHISPER_COREML=ON \
    -DWHISPER_COREML_ALLOW_FALLBACK=ON

cmake --build build-ios-sim --config Release

# Find the static libraries
DEVICE_LIB=$(find build-ios-device -name "libwhisper.a" -type f | head -1)
SIM_LIB=$(find build-ios-sim -name "libwhisper.a" -type f | head -1)

if [ -z "$DEVICE_LIB" ] || [ -z "$SIM_LIB" ]; then
    echo "Error: Could not find static libraries. Checking for alternatives..."
    # Try to create static libraries from dynamic ones if needed
    if [ -f "build-ios-device/src/libwhisper.dylib" ]; then
        echo "Converting dynamic libraries to static..."
        # This is a fallback - ideally we want cmake to build static libs directly
        libtool -static -o build-ios-device/libwhisper.a \
            build-ios-device/src/libwhisper.dylib \
            build-ios-device/ggml/src/libggml.dylib 2>/dev/null || true
        
        libtool -static -o build-ios-sim/libwhisper.a \
            build-ios-sim/src/libwhisper.dylib \
            build-ios-sim/ggml/src/libggml.dylib 2>/dev/null || true
    fi
    
    DEVICE_LIB="build-ios-device/libwhisper.a"
    SIM_LIB="build-ios-sim/libwhisper.a"
fi

echo "Device lib: $DEVICE_LIB"
echo "Simulator lib: $SIM_LIB"

# Create XCFramework
echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers include \
    -library "$SIM_LIB" -headers include \
    -output ../whisper.xcframework

cd ..

echo "✅ whisper.xcframework built successfully!"
echo "Add whisper.xcframework to your Xcode project to use it."