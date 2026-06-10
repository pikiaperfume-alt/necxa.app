import 'dart:io';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

/// Converts raw backend exceptions and network errors into clean, user-friendly messages.
String getUserFriendlyError(dynamic error) {
  if (error == null) return "An unknown error occurred. Please try again.";

  final errorStr = error.toString().toLowerCase();

  // Network / Socket Exceptions
  if (error is SocketException || errorStr.contains('socketexception') || errorStr.contains('failed host lookup')) {
    return "No internet connection. Please check your network and try again.";
  }

  if (error is TimeoutException || errorStr.contains('timeout')) {
    return "Connection timed out. Please try again.";
  }

  // Supabase Auth Exceptions
  if (error is AuthException) {
    if (error.message.toLowerCase().contains('invalid login credentials')) {
      return "Invalid email or verification code. Please check and try again.";
    }
    if (error.message.toLowerCase().contains('rate limit')) {
      return "Too many requests. Please wait a moment before trying again.";
    }
    if (error.message.toLowerCase().contains('expired')) {
      return "The magic link or code has expired. Please request a new one.";
    }
    return error.message; // AuthException messages are usually somewhat clean, but fallback if needed.
  }

  // Platform Exceptions (e.g., Camera, Biometrics)
  if (error is PlatformException) {
    if (error.code == 'NotAvailable') {
      return "This feature is not available on your device.";
    }
    return "A device error occurred. Please try again.";
  }

  // Fallback Catch-All
  // If the error contains raw backend URLs or keys, we MUST mask it.
  if (errorStr.contains('supabase.co') || errorStr.contains('apikey') || errorStr.contains('http')) {
    return "Loading unsuccessful. Please check your connection and try again.";
  }

  // Return a generic safe message for any other raw exceptions
  return "Loading unsuccessful. Please try again.";
}
