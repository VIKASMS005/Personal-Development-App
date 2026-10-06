import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'providers/app_providers.dart';
import 'utils/ui.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AI is optional; a missing local configuration must not prevent the app
  // from starting or make the rest of the product unavailable.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  // Initialize SQLite database
  await DatabaseService.instance.database;

  // Initialize Notifications
  await NotificationService.init();

  // Schedule daily 8:50 AM analytics digest notification
  await NotificationService.scheduleDailyDigest();

  runApp(const RootApp());
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => JournalProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => TimetableProvider()),
        ChangeNotifierProvider(create: (_) => ChatbotProvider()),
        ChangeNotifierProvider(create: (_) => ReminderProvider()),
        ChangeNotifierProvider(create: (_) => AlarmProvider()),
        ChangeNotifierProvider(create: (_) => EngineProvider()),
        ChangeNotifierProvider(create: (_) => TaskTrackerProvider()),
        ChangeNotifierProvider(create: (_) => StepProvider()),
        ChangeNotifierProvider(create: (_) => ScreenTimeProvider()),
      ],
      child: const GrowApp(),
    );
  }
}

class GrowApp extends StatelessWidget {
  const GrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Grow — Personal Development',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.themeMode,
      home: auth.isLoading ? const SplashScreen() : const HomeScreen(),
    );
  }
}
