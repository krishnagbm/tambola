import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/constants/app_assets.dart';
import 'package:tambola/core/theme/app_theme.dart';
import 'package:tambola/features/home/widgets/dashboard_footer.dart';
import 'package:tambola/features/home/widgets/dashboard_hero_section.dart';
import 'package:tambola/features/home/widgets/how_it_works_section.dart';
import 'package:tambola/features/home/widgets/opening_screen.dart';
import 'package:tambola/features/home/widgets/organizer_player_split.dart';
import 'package:tambola/features/home/widgets/perfect_for_chips_section.dart';
import 'package:tambola/features/home/widgets/usp_grid_section.dart';

void main() {
  test('App theme Party Mode configuration verification', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
    expect(theme.colorScheme.primary, const Color(0xFF0B3D91)); // Navy
    expect(theme.colorScheme.secondary, const Color(0xFFFFC107)); // Yellow
    expect(AppTheme.accentSuccess, const Color(0xFF2ECC71)); // Brand Green
    expect(AppTheme.accentDanger, const Color(0xFFE63946)); // Brand Red
    expect(AppTheme.accentPartyPurple, const Color(0xFF8E44AD)); // Brand Purple
  });

  test('DebHousie brand assets paths verification', () {
    expect(AppAssets.horizontalLogo, contains('debhousie_horizontal_logo.png'));
    expect(AppAssets.mainLogo, contains('debhousie_main_logo.png'));
    expect(AppAssets.monogramDH, contains('debhousie_monogram_DH.png'));
    expect(AppAssets.appIcon1024, contains('debhousie_app_icon_1024.png'));
    expect(AppAssets.androidIcon512, contains('debhousie_android_icon_512.png'));
    expect(AppAssets.iosIcon1024, contains('debhousie_ios_icon_1024.png'));
    expect(AppAssets.favicon192, contains('debhousie_favicon_192.png'));
  });

  testWidgets('DashboardHeroSection renders eyebrow, headline, subhead, and trust badges', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: DashboardHeroSection()),
      ),
    );

    expect(find.text('🎉 Multiplayer Tambola, Housie & 90-Ball Bingo — Family, Kitty Parties & Events'), findsOneWidget);
    expect(find.text('Multiplayer Tambola, Housie & 90-Ball Bingo.\nAlways Free for Families, Built for Kitty Parties & Events.'), findsOneWidget);
    expect(find.text('Instant digital tickets, guaranteed-unique cards, and automated server-side win verification — no app download needed for guests.'), findsOneWidget);
    expect(find.textContaining('Free Family Play'), findsOneWidget);
    expect(find.textContaining('Host Party'), findsOneWidget);
    expect(find.text('Join Game'), findsOneWidget);
    expect(find.text('📺 Live Projector & TV Mode'), findsOneWidget);
    expect(find.text('⚡ Smart Waitlist Auto-Promotion'), findsOneWidget);
    expect(find.text('✅ 100K+ Unique tickets (8.1T space)'), findsOneWidget);
  });

  testWidgets('OrganizerPlayerSplit renders dual split cards', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SingleChildScrollView(child: OrganizerPlayerSplit())),
      ),
    );

    expect(find.text('Hosting a Family Night, Kitty Party, or Event?'), findsOneWidget);
    expect(find.text('Got an Invite Code?'), findsOneWidget);
    expect(find.text('Create Your Game (Free 1–5) →'), findsOneWidget);
    expect(find.text('Join a Game →'), findsOneWidget);
  });

  testWidgets('UspGridSection renders all 6 proof-based cards', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SingleChildScrollView(child: UspGridSection())),
      ),
    );

    expect(find.text('Why DebHousie?'), findsOneWidget);
    expect(find.text('Fair Play, Guaranteed'), findsOneWidget);
    expect(find.text('100K+ Unique Tickets'), findsOneWidget);
    expect(find.text('Mega-X Enterprise Scale'), findsOneWidget);
    expect(find.text('Custom Winning Patterns'), findsOneWidget);
    expect(find.text('Big-Screen Caller Cast'), findsOneWidget);
    expect(find.text('Instant Guest Join'), findsOneWidget);
  });

  testWidgets('HowItWorksSection and PerfectForChipsSection render properly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                HowItWorksSection(),
                PerfectForChipsSection(),
                DashboardFooter(),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('How It Works'), findsOneWidget);
    expect(find.text('Create your game'), findsOneWidget);
    expect(find.text('Guests join free'), findsOneWidget);
    expect(find.text('Call numbers live'), findsOneWidget);
    expect(find.text('Perfect For Every Celebration'), findsOneWidget);
    expect(find.text('Kitty Parties & Socials'), findsOneWidget);
    expect(find.text('Family Game Nights'), findsOneWidget);
    expect(find.text('Play • Connect • Win'), findsOneWidget);
  });

  testWidgets('OpeningScreen renders with DebHousie tagline and pulsing indicators', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const OpeningScreen(),
      ),
    );

    expect(find.text('Play • Connect • Win'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
