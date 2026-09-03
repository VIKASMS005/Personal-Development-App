import 'package:flutter/material.dart';

/// Central color palette for Grow — Modern Emerald & Slate theme.
class AppColors {
  AppColors._();

  // Brand Primaries
  static const primary = Color(0xFF059669);
  static const primaryLight = Color(0xFF10B981);
  static const primaryDark = Color(0xFF047857);
  static const primaryAccent = Color(0xFF34D399);

  // Secondary & Accents
  static const secondary = Color(0xFF6366F1);
  static const secondaryLight = Color(0xFF818CF8);
  static const accent = Color(0xFFF59E0B);
  static const tertiary = Color(0xFF8B5CF6);

  // Feature Accents
  static const tasks = Color(0xFF3B82F6);
  static const habits = Color(0xFF10B981);
  static const journal = Color(0xFF8B5CF6);
  static const finance = Color(0xFFF59E0B);
  static const timetable = Color(0xFF06B6D4);
  static const calendar = Color(0xFFEC4899);
  static const alarm = Color(0xFFF97316);
  static const chatbot = Color(0xFF6366F1);

  // Light Theme Surfaces
  static const lightBg = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCardHover = Color(0xFFF1F5F9);
  static const lightText = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF334155);
  static const lightBorder = Color(0xFFCBD5E1);

  // Dark Theme Surfaces
  static const darkBg = Color(0xFF0B132B);
  static const darkSurface = Color(0xFF1C2541);
  static const darkCard = Color(0xFF1E293B);
  static const darkCardHover = Color(0xFF334155);
  static const darkText = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFCBD5E1);
  static const darkBorder = Color(0xFF475569);

  // Semantic
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);

  // Gradients
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF047857), Color(0xFF059669), Color(0xFF10B981)],
  );

  static const secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF818CF8)],
  );

  static const authGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF1E1B4B)],
  );

  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF0F172A)],
  );

  static const chatbotGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF06B6D4)],
  );

  static const timetableGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0284C7), Color(0xFF06B6D4), Color(0xFF10B981)],
  );
}
