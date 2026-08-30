# Personal Development App

A Flutter mobile application for personal development and productivity, built with Firebase backend support.

## 📱 Features

- User authentication with Google Sign-In
- Firebase Cloud Firestore integration for real-time data
- Push notifications with Firebase Cloud Messaging
- Image picking and storage
- Offline support with local caching
- Cross-platform support (Android, iOS, Web)
- Responsive UI design

## 🛠️ Prerequisites

Before you begin, ensure you have installed:

- **Flutter SDK** (version 3.0 or higher)
  - Download from [flutter.dev](https://flutter.dev)
- **Dart** (comes with Flutter)
- **Android Studio** or **Xcode** (for mobile development)
- **Git** (for version control)

## 📦 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/VIKASMS005/Personal-Development-App.git
   cd Personal-Development-App/flutter_application_1
   ```

2. **Set up environment variables:**
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and add your Firebase credentials and API keys

   See [SETUP.md](SETUP.md) for detailed environment setup instructions.

3. **Get Flutter dependencies:**
   ```bash
   flutter pub get
   ```

4. **Configure Firebase:**
   - Download `google-services.json` from Firebase Console and place in `android/app/`
   - Download `GoogleService-Info.plist` and add to iOS Runner project in Xcode

## 🚀 Running the App

### Run on Android:
```bash
flutter run -d android
```

### Run on iOS:
```bash
flutter run -d ios
```

### Run on Web:
```bash
flutter run -d chrome
```

### Run with a specific device:
```bash
flutter devices  # List all available devices
flutter run -d <device_id>
```

## 📁 Project Structure

```
flutter_application_1/
├── lib/
│   ├── main.dart              # App entry point
│   ├── constants/             # App constants and configuration
│   ├── models/                # Data models
│   ├── providers/             # State management (Provider pattern)
│   ├── screens/               # UI screens/pages
│   ├── services/              # Business logic and API services
│   ├── utils/                 # Utility functions and helpers
│   └── widgets/               # Reusable widgets
├── android/                   # Android native code
├── ios/                       # iOS native code
├── web/                       # Web platform code
├── pubspec.yaml               # Flutter dependencies
├── .env.example               # Environment variables template
├── SETUP.md                   # Environment setup guide
└── README.md                  # This file
```

## 🔒 Security

- **API Keys**: Never commit sensitive data. Use `.env` file for local configuration.
- **Firebase Config**: `google-services.json` and `GoogleService-Info.plist` are in `.gitignore`
- **Environment Variables**: Create `.env` from `.env.example` locally

For detailed security setup, see [SETUP.md](SETUP.md).

## 📚 Dependencies

Main packages used:
- **firebase_core** - Firebase initialization
- **cloud_firestore** - Realtime database
- **firebase_auth** - Authentication
- **firebase_messaging** - Push notifications
- **google_sign_in** - Google authentication
- **provider** - State management
- **image_picker** - Image selection
- **flutter_local_notifications** - Local notifications
- **connectivity_plus** - Network connectivity

See `pubspec.yaml` for the complete list of dependencies.

## 🔧 Development

### Hot Reload (while app is running):
```bash
Press 'r' in terminal to hot reload
Press 'R' to hot restart
```

### Run Tests:
```bash
flutter test
```

### Build Release APK (Android):
```bash
flutter build apk --release
```

### Build Release IPA (iOS):
```bash
flutter build ios --release
```

## 📝 Environment Variables

The app uses `.env` file for configuration. See `.env.example` for all required variables:

- Firebase credentials
- Google Sign-In credentials
- API keys
- App environment settings
- Debug mode configuration

## 🤝 Contributing

Contributions are welcome! Please:

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Commit your changes: `git commit -m 'Add your feature'`
3. Push to the branch: `git push origin feature/your-feature`
4. Open a Pull Request

## 🐛 Known Issues

- None currently reported

Please report any bugs you find!

## 📄 License

This project is private. Contact the owner for usage rights.

## 👤 Author

**VIKASMS005**

- GitHub: [@VIKASMS005](https://github.com/VIKASMS005)
- Repository: [Personal-Development-App](https://github.com/VIKASMS005/Personal-Development-App)

## 📞 Support

For support, please open an issue on the GitHub repository.

## 🔄 Next Steps

1. Configure Firebase in your project
2. Set up your `.env` file with credentials
3. Install dependencies with `flutter pub get`
4. Run the app with `flutter run`

Happy coding! 🎉
