import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';

/// Dual-audience card section on HomeScreen presenting balanced cards:
/// 1) Family, Friends & Weekend Parties (ad-hoc games, free family pack, everyone wins, no one pays anything)
/// 2) Corporate & Event Hosts (team building, 1-ticket fairness, enterprise security)
class DabhousieCorporateUspCard extends StatelessWidget {
  const DabhousieCorporateUspCard({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFamilyCard(context)),
              const SizedBox(width: 14),
              Expanded(child: _buildCorporateCard(context)),
            ],
          );
        }

        return Column(
          children: [
            _buildFamilyCard(context),
            const SizedBox(height: 14),
            _buildCorporateCard(context),
          ],
        );
      },
    );
  }

  Widget _buildFamilyCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF221A0F),
            Color(0xFF0F1522),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Tag & Free Hint
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏡', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 6),
                    Text(
                      'FOR FAMILY & FRIENDS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFBBF24),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '100% Free (Up to 5)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Headline & Motto
          const Text(
            'Instant Fun for Family Get-Togethers & Parties',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Host ad-hoc games in 30 seconds for weekend fun, festivals, and kitty parties. Everyone wins with exciting patterns, automatic calling, and pure social laughter.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Mini USP Pills Wrap
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildBadge('🎉 Ad-hoc Quick Games'),
              _buildBadge('🏆 Everyone Wins'),
              _buildBadge('👨‍👩‍👧‍👦 Family Pack Up to 5 Free'),
              _buildBadge('⚡ Instant Web Play (No App)'),
              _buildBadge('✨ No One Pays Anything*'),
            ],
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 6,
                child: OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse('${AppConfig.appBaseUrl}/how-to-play-tambola.html'),
                      webOnlyWindowName: '_self',
                    );
                  },
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: const Text(
                    'How to Play',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: const BorderSide(color: Color(0xFFF59E0B), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/create-game'),
                  icon: const Icon(Icons.celebration_rounded, size: 16),
                  label: const Text(
                    'Host Free Game',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCorporateCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF131D36),
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Tag & Mascot hint
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏢', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 6),
                    Text(
                      'FOR CORPORATES & EVENT HOSTS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF38BDF8),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '100% Free for Guests',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Headline & Motto
          const Text(
            'Built for Team Building — Strictly NOT Gambling',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Every player gets strictly 1 unique ticket for 100% fair winning odds. The autonomous caller frees the host to play too, with host OTP privacy and zero-loss quorum control.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Mini USP Pills Wrap
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildBadge('🎟️ 1 Ticket = Fair Odds'),
              _buildBadge('🧠 Cognitive Recall Trivia'),
              _buildBadge('🎮 Host Plays Too'),
              _buildBadge('🔒 Host OTP Security'),
              _buildBadge('🛡️ Quorum Protected'),
              _buildBadge('🎁 Brand Gifts (No Cash)'),
            ],
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 6,
                child: OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse('${AppConfig.appBaseUrl}/why-dabhousie.html'),
                      webOnlyWindowName: '_self',
                    );
                  },
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text(
                    'Why DabHousie?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/create-game'),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text(
                    'Host Game (\$2–\$10)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}

typedef DabhousieDualAudienceCards = DabhousieCorporateUspCard;
