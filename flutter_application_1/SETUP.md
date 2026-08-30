# Environment Setup Guide

## Prerequisites
- Copy `.env.example` to `.env`
- Fill in your actual API keys and configuration values in `.env`

## Setting Up Environment Variables

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your actual credentials:**
   - Get your Firebase credentials from Firebase Console
   - Add your Google Sign-In credentials
   - Add any other API keys your app requires

3. **Load environment variables in your app:**
   - For Flutter, you can use the `flutter_dotenv` package
   - Or manually read from a config file

## Important Security Notes

⚠️ **NEVER commit `.env` to version control!**
- The `.env` file is listed in `.gitignore` and won't be committed
- Only `.env.example` is committed as a template
- Each developer should have their own `.env` file locally

## Protected Files

The following files are automatically excluded from git:
- `.env` - Local environment variables
- `android/app/google-services.json` - Android Firebase config
- `ios/Runner/GoogleService-Info.plist` - iOS Firebase config
- Other sensitive configuration files

## Setup Steps for New Developers

1. Clone the repository
2. Copy `.env.example` to `.env`
3. Fill in the `.env` file with your credentials
4. Install dependencies: `flutter pub get`
5. Run the app: `flutter run`

## Firebase Configuration

You'll need to:
1. Create a Firebase project
2. Download `google-services.json` for Android and place it in `android/app/`
3. Download `GoogleService-Info.plist` for iOS and add it to Xcode project
4. Copy Firebase config values to `.env`

**Note:** These files should NOT be committed to the repository.
