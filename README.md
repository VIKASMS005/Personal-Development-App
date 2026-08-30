# Personal Development App

A smart and focused Flutter mobile app designed to help users build better routines, stay disciplined, and improve personal growth through productivity, reflection, health, and learning tools.

## Overview

The Personal Development App combines daily planning, habit tracking, mental wellness, personal finance tracking, and AI-assisted guidance in one place. It is built for users who want a practical dashboard for managing their life more intentionally.

## Key Features

- Habit tracking and streak monitoring
- Todo and task planning with reminders
- Journal and personal reflection entries
- Finance tracking and expense insights
- Timetable and daily scheduling
- AI coach/chatbot support for motivation and productivity tips
- Alarm and reminder notifications
- Wellness/step tracking and screen-time monitoring
- Offline-first local data storage with SQLite
- Clean, modern interface with light/dark theme support

## Tech Stack

- Flutter
- Dart
- Provider for state management
- SQLite for local persistence
- Google Generative AI integration
- Flutter local notifications
- SharedPreferences and path-based storage support

## Project Structure

```text
Personal Development App/
├── README.md
├── LICENSE
├── .gitignore
├── flutter_application_1/
│   ├── android/
│   ├── ios/
│   ├── lib/
│   ├── web/
│   ├── windows/
│   ├── linux/
│   ├── macos/
│   ├── pubspec.yaml
│   ├── .env.example
│   ├── SETUP.md
│   └── README.md
└── .vscode/
```

## Getting Started

### 1) Clone the repository

```bash
git clone https://github.com/VIKASMS005/Personal-Development-App.git
cd Personal-Development-App
```

### 2) Install dependencies

```bash
cd flutter_application_1
flutter pub get
```

### 3) Configure environment variables

Copy the example environment file and add your API key:

```bash
cp .env.example .env
```

Then edit the `.env` file and add your Gemini API key:

```env
GEMINI_API_KEY=your_gemini_api_key_here
```

### 4) Run the app

#### Android

```bash
flutter run -d android
```

#### Web

```bash
flutter run -d chrome
```

#### iOS

```bash
flutter run -d ios
```

## Environment and Setup Notes

- Keep the `.env` file local and never commit it to source control.
- Firebase and platform config files are also excluded from git tracking.
- For detailed setup and environment instructions, refer to `flutter_application_1/SETUP.md`.

## Features in Detail

### Productivity
- Todo management
- Goal-oriented planning
- Daily schedule and time blocking

### Personal Growth
- Habit streaks and consistency tracking
- Reflection journaling
- AI-based coaching guidance

### Wellness
- Step tracking
- Screen-time insights
- Daily reminders and health-focused alerts

### Financial Awareness
- Expense tracking
- Budget and balance overview

## Contributing

Contributions are welcome. If you would like to improve the app:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a pull request

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Author

VIKASMS005

GitHub: https://github.com/VIKASMS005

## Repository

https://github.com/VIKASMS005/Personal-Development-App
