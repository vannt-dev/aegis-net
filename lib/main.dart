import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'src/providers/vpn_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/screens/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const AegisApp(),
    ),
  );
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'AegisNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        primaryColor: theme.primaryAccent,
        textTheme: _outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// google_fonts 9 builds its text themes on the material_ui package, whose
// TextTheme is not the type package:flutter/material.dart uses, so each
// style gets the font here.
TextTheme _outfitTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: GoogleFonts.outfit(textStyle: base.displayLarge),
    displayMedium: GoogleFonts.outfit(textStyle: base.displayMedium),
    displaySmall: GoogleFonts.outfit(textStyle: base.displaySmall),
    headlineLarge: GoogleFonts.outfit(textStyle: base.headlineLarge),
    headlineMedium: GoogleFonts.outfit(textStyle: base.headlineMedium),
    headlineSmall: GoogleFonts.outfit(textStyle: base.headlineSmall),
    titleLarge: GoogleFonts.outfit(textStyle: base.titleLarge),
    titleMedium: GoogleFonts.outfit(textStyle: base.titleMedium),
    titleSmall: GoogleFonts.outfit(textStyle: base.titleSmall),
    bodyLarge: GoogleFonts.outfit(textStyle: base.bodyLarge),
    bodyMedium: GoogleFonts.outfit(textStyle: base.bodyMedium),
    bodySmall: GoogleFonts.outfit(textStyle: base.bodySmall),
    labelLarge: GoogleFonts.outfit(textStyle: base.labelLarge),
    labelMedium: GoogleFonts.outfit(textStyle: base.labelMedium),
    labelSmall: GoogleFonts.outfit(textStyle: base.labelSmall),
  );
}
