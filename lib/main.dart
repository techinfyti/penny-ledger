import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import 'services/account_service.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'services/budget_service.dart';
import 'services/category_service.dart';
import 'services/csv_export_service.dart';
import 'services/currency_service.dart';
import 'services/drive_backup_service.dart';
import 'services/firestore_service.dart';
import 'services/group_service.dart';
import 'services/notification_service.dart';
import 'services/pdf_report_service.dart';
import 'services/premium_service.dart';
import 'services/purchase_service.dart';
import 'services/recurring_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Firebase.initializeApp();
  final currencyService = CurrencyService();
  await currencyService.load();
  final appLockService = AppLockService();
  await appLockService.load();
  final themeService = ThemeService();
  await themeService.load();
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermission();
  await MobileAds.instance.initialize();
  runApp(DailyExpenseApp(
    currencyService: currencyService,
    appLockService: appLockService,
    themeService: themeService,
    notificationService: notificationService,
  ));
}

class DailyExpenseApp extends StatelessWidget {
  final CurrencyService currencyService;
  final AppLockService appLockService;
  final ThemeService themeService;
  final NotificationService notificationService;

  const DailyExpenseApp({
    super.key,
    required this.currencyService,
    required this.appLockService,
    required this.themeService,
    required this.notificationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        Provider<CategoryService>(create: (_) => CategoryService()),
        Provider<PdfReportService>(create: (_) => PdfReportService()),
        Provider<CsvExportService>(create: (_) => CsvExportService()),
        Provider<BudgetService>(create: (_) => BudgetService()),
        Provider<GroupService>(create: (_) => GroupService()),
        Provider<RecurringService>(create: (context) => RecurringService(context.read<FirestoreService>())),
        Provider<DriveBackupService>(
          create: (context) => DriveBackupService(context.read<AuthService>().googleSignIn),
        ),
        Provider<NotificationService>.value(value: notificationService),
        ChangeNotifierProvider<CurrencyService>.value(value: currencyService),
        ChangeNotifierProvider<AppLockService>.value(value: appLockService),
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ChangeNotifierProvider<AccountService>(create: (_) => AccountService()),
        ChangeNotifierProvider<PremiumService>(create: (_) => PremiumService()),
        ProxyProvider<PremiumService, PurchaseService>(
          update: (context, premiumService, previous) => previous ?? PurchaseService(premiumService),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) {
          final color = themeService.color;
          return MaterialApp(
            title: 'PennyLedger',
            theme: ThemeData(
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: color.seed,
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: color.background,
              appBarTheme: AppBarTheme(
                backgroundColor: color.appBarColor,
                foregroundColor: Colors.white,
                iconTheme: const IconThemeData(color: Colors.white),
                actionsIconTheme: const IconThemeData(color: Colors.white),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: color.appBarColor,
                indicatorColor: Colors.white.withOpacity(0.2),
                labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
                iconTheme: WidgetStateProperty.all(
                  const IconThemeData(color: Colors.white),
                ),
              ),
              useMaterial3: true,
            ),
            home: const AppLockGate(child: AuthGate()),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        return HomeScreen(uid: user.uid);
      },
    );
  }
}
