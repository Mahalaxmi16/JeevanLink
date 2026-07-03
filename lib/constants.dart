import 'package:flutter_dotenv/flutter_dotenv.dart';

// This is where you will put your Supabase project's URL and public 'anon' key.
// You can find these in your Supabase project's dashboard under Project Settings > API.
// IMPORTANT: REPLACE THESE EMPTY STRINGS WITH YOUR ACTUAL KEYS.
const String supabaseUrl = 'https://wojacfyqtkjoirskafor.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndvamFjZnlxdGtqb2lyc2thZm9yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcxNTMyMTgsImV4cCI6MjA3MjcyOTIxOH0.DLTOSIvdTklmsY7INj3OoOJxdOrUUeXnLCqc2r5Jx80';

// TODO: Replace with your actual MSG91 SendOTP widget credentials (replace with real values, keep secrets out of source control)
const String msg91WidgetId = '356b73704a52313135353830';
final String msg91AuthToken = dotenv.env['MSG91_AUTH_TOKEN'] ?? '';
String get fast2SmsApiKey => dotenv.env['FAST2SMS_API_KEY'] ?? '';