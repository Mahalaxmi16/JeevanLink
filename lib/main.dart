// main.dart
import 'package:flutter/material.dart';
import 'package:jeevanlink/constants.dart';
import 'package:jeevanlink/services/msg91_otp_service.dart';
import 'package:jeevanlink/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jeevanlink/notification_service.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  
  // Initialize local notification service
  await NotificationService().init();
  
  await Msg91OtpService.instance.init(
    widgetId: msg91WidgetId,
    authToken: msg91AuthToken,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JeevanLink',
      theme: ThemeData(
        primarySwatch: Colors.red,
        fontFamily: 'Inter',
      ),
      home: const SplashScreen(),
    );
  }
}
