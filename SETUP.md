# Setting up WalkWrite for Development

This guide will help you set up WalkWrite for local development.

## Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Git with LFS support
- CMake (for building whisper.cpp)
- At least 10GB free disk space

## Step 1: Clone the Repository

```bash
# Clone with Git LFS
git clone https://github.com/yourusername/WalkWrite.git
cd WalkWrite

# Ensure Git LFS is installed
git lfs install

# Pull the large model files
git lfs pull
```

## Step 2: Build whisper.cpp Framework

WalkWrite uses whisper.cpp for speech recognition. You need to build it as an XCFramework:

```bash
# Run the build script
./build-whisper-xcframework.sh
```

This will:
1. Clone whisper.cpp if needed
2. Build for both iOS device and simulator
3. Create `whisper.xcframework` in the project root

**Note**: The project expects the framework at `Vendor/whisper.cpp/build-apple/whisper.xcframework`. After building, either:
- Move the framework to that location: `mkdir -p Vendor/whisper.cpp/build-apple && mv whisper.xcframework Vendor/whisper.cpp/build-apple/`
- Or update the framework path in Xcode

## Step 3: Configure Your Development Team

1. Copy the configuration template:
   ```bash
   cp Config.xcconfig.template Config.xcconfig
   ```

2. Edit `Config.xcconfig` with your development team ID:
   - Find your Team ID in Xcode → Preferences → Accounts
   - Or leave empty for personal development

3. Update the bundle identifier prefix to your organization

## Step 4: Add Dependencies to Xcode

1. Open `WalkWrite.xcodeproj` in Xcode
2. Add `whisper.xcframework` to the project:
   - Select the WalkWrite project in the navigator
   - Select the WalkWrite target
   - Go to "Frameworks, Libraries, and Embedded Content"
   - Click "+" and add `whisper.xcframework`
   - Ensure "Embed & Sign" is selected

## Step 4: Configure MLX Swift Package

The project uses MLX Swift for running the Qwen language model. This should be automatically resolved by Xcode through Swift Package Manager.

If needed, add it manually:
1. File → Add Package Dependencies
2. Enter: `https://github.com/ml-explore/mlx-swift`
3. Add to the WalkWrite target

## Step 5: Verify Model Files

Ensure these large model files are present:
- `WalkWrite/QwenModel/` - Qwen language model (~1.4GB)
- `WalkWrite/ggml-large-v3-turbo-q5_0.bin` - Whisper model (~574MB)
- `WalkWrite/ggml-large-v3-turbo-encoder.mlmodelc/` - Core ML encoder

## Step 6: Build and Run

1. Select your target device (physical iOS device recommended)
2. Build and run (⌘R)

**Note**: The first launch will take longer as Core ML compiles the models for your specific device.

## Troubleshooting

### "Missing whisper.xcframework"
Run `./build-whisper-xcframework.sh` to build it.

### "Model files are missing"
Ensure you ran `git lfs pull` to download the large files.

### "Missing package product 'MLXLMCommon'" or other Swift Package errors
This is a common Xcode package resolution issue. To fix:

1. Run the reset script:
   ```bash
   ./reset-packages.sh
   ```

2. Open the project in Xcode and wait for package resolution

3. If still failing, in Xcode:
   - File → Packages → Reset Package Caches
   - File → Packages → Update to Latest Package Versions
   - Clean build folder (⇧⌘K)

4. Be patient - initial MLX package download can take 5-10 minutes

### "Build fails on simulator"
The app is optimized for real devices. Some features may not work correctly on the simulator due to Metal/Core ML requirements.

### Memory warnings
The app uses significant memory when running AI models. Close other apps if you experience issues.

## Development Tips

- Use a physical device for testing transcription and LLM features
- The app supports background audio recording
- All AI processing is done on-device for privacy
- Models are loaded on-demand to manage memory

## Optional: Customizing Models

To use different Whisper models:
1. Download a different `.bin` model from whisper.cpp
2. Replace `ggml-large-v3-turbo-q5_0.bin`
3. Update the model name in `WhisperEngine.swift`

To use a different LLM:
1. Ensure it's compatible with MLX Swift
2. Replace the `QwenModel` directory
3. Update `LLMEngine.swift` configuration

## Support

If you encounter issues:
1. Check the [Issues](https://github.com/yourusername/WalkWrite/issues) page
2. Ensure you're using the correct Xcode and iOS versions
3. Try cleaning the build folder (⇧⌘K) and rebuilding