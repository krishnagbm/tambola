import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

enum GuideCategory {
  cash,
  brandGifts,
  physicalTrophies,
  dabhousieCredits,
  autonomousDabby,
}

class KnowledgeHubSection extends StatefulWidget {
  const KnowledgeHubSection({super.key});

  @override
  State<KnowledgeHubSection> createState() => _KnowledgeHubSectionState();
}

class _KnowledgeHubSectionState extends State<KnowledgeHubSection> {
  GuideCategory _selectedCategory = GuideCategory.cash;
  bool _isHostPerspective = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppTheme.primaryLight,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Player & Host Knowledge Hub',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.all(Radius.circular(4)),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text(
                                'GUIDES',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryLight,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        'How-to workflows for prize claims, payouts & auto-calling',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Category Chips Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _buildCategoryChip(
                  GuideCategory.cash,
                  '💵 Cash & Mobile Pay',
                  const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  GuideCategory.brandGifts,
                  '🛍️ Brand Gift Cards',
                  const Color(0xFFEC4899),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  GuideCategory.physicalTrophies,
                  '🏆 Trophies & QR Pass',
                  const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  GuideCategory.dabhousieCredits,
                  '🎁 Hosting Credits',
                  AppTheme.secondaryColor,
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  GuideCategory.autonomousDabby,
                  '⚙️ Autonomous Dabby',
                  AppTheme.primaryLight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Perspective Switcher (Host vs Player)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFF121526),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isHostPerspective = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _isHostPerspective
                              ? AppTheme.secondaryColor.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: _isHostPerspective
                              ? Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              size: 15,
                              color: _isHostPerspective
                                  ? AppTheme.secondaryColor
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '👑 Host / Organizer Guide',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _isHostPerspective ? FontWeight.bold : FontWeight.normal,
                                color: _isHostPerspective
                                    ? AppTheme.secondaryColor
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _isHostPerspective = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: !_isHostPerspective
                              ? AppTheme.primaryLight.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: !_isHostPerspective
                              ? Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.confirmation_number_outlined,
                              size: 15,
                              color: !_isHostPerspective
                                  ? AppTheme.primaryLight
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '🎟️ Player / Guest Guide',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: !_isHostPerspective ? FontWeight.bold : FontWeight.normal,
                                color: !_isHostPerspective
                                    ? AppTheme.primaryLight
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Active Guide Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildActiveGuideContent(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(GuideCategory cat, String label, Color accentColor) {
    final isSelected = _selectedCategory == cat;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = cat),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.2) : const Color(0xFF121526),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF2E334D),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveGuideContent(BuildContext context) {
    switch (_selectedCategory) {
      case GuideCategory.cash:
        return _buildCashGuide(context);
      case GuideCategory.brandGifts:
        return _buildBrandGiftsGuide(context);
      case GuideCategory.physicalTrophies:
        return _buildPhysicalTrophiesGuide(context);
      case GuideCategory.dabhousieCredits:
        return _buildHostingCreditsGuide(context);
      case GuideCategory.autonomousDabby:
        return _buildAutonomousDabbyGuide(context);
    }
  }

  // ==========================================
  // 1. CASH & MOBILE PAY GUIDE
  // ==========================================
  Widget _buildCashGuide(BuildContext context) {
    if (_isHostPerspective) {
      return _buildGuideCard(
        title: 'Settling with Cash / Venmo / Zelle / UPI',
        subtitle: 'When awarding cash or direct mobile money transfers to winners',
        accentColor: const Color(0xFF10B981),
        steps: const [
          'Open "Organizer Prize Claims & Brand Gift Hub" or click "Settle" from your game lobby.',
          'Review the winning player name, ticket number, and prize won (e.g., Full Housie \$10).',
          'Ask the winner for their payment handle (Venmo @handle, Zelle phone/email, or UPI ID) and cross-verify their Ticket # and Prize Voucher Code.',
          'Send the payment directly via your mobile banking or payment app.',
          'In DabHousie, select "Direct Cash / UPI / Venmo / Zelle", enter the transaction reference or note, and tap "Mark Settled & Complete".',
        ],
        tipText: '💡 Zero commissions! DabHousie does not touch player cash prize transactions, so 100% of your payout reaches the winner directly.',
        actionLabel: 'Open Organizer Prize Claims',
        actionIcon: Icons.receipt_long_rounded,
        onAction: () => context.push('/wallet/claims'),
      );
    } else {
      return _buildGuideCard(
        title: 'Receiving Cash / Venmo / Zelle / UPI Payouts',
        subtitle: 'How to claim and receive your cash prize from the game host',
        accentColor: const Color(0xFF10B981),
        steps: const [
          'When Dabby announces your win, tap your winning ticket or go to "My Rewards & Vouchers".',
          'Locate your unique 8-character Prize Voucher Code and your 6-digit Ticket Number.',
          'Share your Venmo handle, Zelle email/phone, UPI ID, or meet in-person for cash.',
          'Provide your Ticket Number & Voucher Code to the host so they can verify the win against their game records.',
          'Once the host completes the transfer, your claim will be marked as "Settled" in your Rewards history.',
        ],
        tipText: '🔒 Keep your Voucher Code safe! It confirms your win ownership in case you played as a guest or on a shared device.',
        actionLabel: 'View My Rewards & Vouchers',
        actionIcon: Icons.emoji_events_outlined,
        onAction: () => context.push('/rewards'),
      );
    }
  }

  // ==========================================
  // 2. BRAND PARTNER GIFTS GUIDE
  // ==========================================
  Widget _buildBrandGiftsGuide(BuildContext context) {
    if (_isHostPerspective) {
      return _buildGuideCard(
        title: 'Allocating Brand Partner Digital Gift Cards',
        subtitle: 'Amazon, Starbucks, Netflix, Apple, Uber & JBL gift cards',
        accentColor: const Color(0xFFEC4899),
        steps: const [
          'Visit the "Organizer Prize Claims & Brand Gift Hub" from your profile or wallet.',
          'Select the winning claim for the game and choose "Brand Partner Gift Card".',
          'Choose the brand (e.g. Amazon \$10, Starbucks \$5) from the sponsored brand catalog.',
          'Confirm allocation: DabHousie automatically generates the digital gift card code & claim link.',
          'The gift code is immediately dispatched to the winner\'s registered email and stored in their in-app Rewards Locker.',
        ],
        tipText: '🎉 Brand gifts can be purchased with organizer event credits or discounted corporate package credits!',
        actionLabel: 'Browse Brand Gift Hub',
        actionIcon: Icons.card_giftcard_rounded,
        onAction: () => context.push('/wallet/claims'),
      );
    } else {
      return _buildGuideCard(
        title: 'Redeeming Your Brand Partner Gift Card',
        subtitle: 'Instant redemption for Amazon, Starbucks, Apple and partner cards',
        accentColor: const Color(0xFFEC4899),
        steps: const [
          'When the host allocates a brand gift card, check your registered email or open "My Rewards & Vouchers".',
          'Find your winning prize card and tap "Reveal Claim Code".',
          'Tap "Redeem on Partner Site" to auto-open Amazon / Starbucks and apply the gift balance to your account.',
          'Copy the alphanumeric code for backup or gift it to a family member anytime.',
        ],
        tipText: '✨ All brand gift cards are 100% genuine digital vouchers with no expiry and instant activation.',
        actionLabel: 'Check My Rewards Locker',
        actionIcon: Icons.card_giftcard_rounded,
        onAction: () => context.push('/rewards'),
      );
    }
  }

  // ==========================================
  // 3. PHYSICAL TROPHIES & QR PASS GUIDE
  // ==========================================
  Widget _buildPhysicalTrophiesGuide(BuildContext context) {
    if (_isHostPerspective) {
      return _buildGuideCard(
        title: 'Scanning & Verifying Physical Prizes at Events',
        subtitle: 'Handing out trophies, medals, chocolates & festival gift hampers',
        accentColor: const Color(0xFFF59E0B),
        steps: const [
          'Open "Organizer Prize Verification" on your mobile browser or DabHousie app.',
          'Tap "Scan Winner QR Pass" to activate your camera, or type the winner\'s Voucher Code manually.',
          'Point your camera at the player\'s phone screen showing their dynamic QR pass.',
          'DabHousie will instantly verify the ticket authenticity, game title, and prize category on screen.',
          'Hand over the physical prize and tap "Confirm Handover & Settle" to update real-time records.',
        ],
        tipText: '🛡️ Instant fraud protection: Tamper-proof QR codes prevent duplicated screenshots or false claims during busy live events.',
        actionLabel: 'Open QR Verification Scanner',
        actionIcon: Icons.qr_code_scanner,
        onAction: () => context.push('/verify-reward'),
      );
    } else {
      return _buildGuideCard(
        title: 'Showing Your Live QR Pass for Physical Prizes',
        subtitle: 'Collecting trophies, medals and festival hampers at the venue',
        accentColor: const Color(0xFFF59E0B),
        steps: const [
          'Open "My Rewards & Vouchers" in your DabHousie app or mobile browser.',
          'Tap on your winning prize item to view your full-screen Live QR Pass.',
          'Walk up to the organizer or event stage desk.',
          'Present your screen to the host for a quick camera scan.',
          'Collect your physical award or gift hamper upon confirmation!',
        ],
        tipText: '📱 No internet at the stage? The voucher code displayed right below the QR code can be manually typed by the host.',
        actionLabel: 'Show My Prize Passes',
        actionIcon: Icons.qr_code_rounded,
        onAction: () => context.push('/rewards'),
      );
    }
  }

  // ==========================================
  // 4. DABHOUSIE EVENT CREDITS GUIDE
  // ==========================================
  Widget _buildHostingCreditsGuide(BuildContext context) {
    if (_isHostPerspective) {
      return _buildGuideCard(
        title: 'Awarding DabHousie Event Hosting Credits',
        subtitle: 'Turn winners into future game hosts with free hosting credits',
        accentColor: AppTheme.secondaryColor,
        steps: const [
          'In the Settle Prize dialog, select "DabHousie Event Credits".',
          'The system converts the cash prize value into hosting credits at \$1 = 5 credits (e.g. \$10 = 50 credits).',
          'If the winner is a registered player, credits are credited directly to their organizer wallet balance.',
          'If the winner is a guest player, a secure Unique Voucher Code is generated.',
          'The guest can sign up or log in anytime from the Profile section to redeem their 50 hosting credits!',
        ],
        tipText: '🚀 Awarding hosting credits builds community: winners use their credits to host family get-togethers, festival games & office parties!',
        actionLabel: 'Manage Game Claims',
        actionIcon: Icons.account_balance_wallet_outlined,
        onAction: () => context.push('/wallet/claims'),
      );
    } else {
      return _buildGuideCard(
        title: 'Redeeming Prize Vouchers for Free Hosting Credits',
        subtitle: 'Convert your win into 50+ credits to host games for your friends & family',
        accentColor: AppTheme.secondaryColor,
        steps: const [
          'If you won a prize as a Guest, locate your Voucher Code from your winning ticket or game screen.',
          'Sign in or create a free DabHousie account via Google or Email in the Profile tab.',
          'Open "Organizer Credits & Wallet" from your profile.',
          'Scroll down to "Redeem Prize Voucher for Credits" and paste your 8-character Voucher Code.',
          'If prompted, enter your winning 6-digit Ticket Number & Game Invite Code to verify ownership.',
          '50 hosting credits will instantly be credited to your wallet balance. Host games without paying a dime!',
        ],
        tipText: '🔒 Anti-theft protection: Live stream spectators cannot steal your voucher code because redemption requires your exact Ticket Number and Game Invite Code.',
        actionLabel: 'Redeem Voucher in Wallet',
        actionIcon: Icons.redeem_rounded,
        onAction: () => context.push('/wallet'),
      );
    }
  }

  // ==========================================
  // 5. AUTONOMOUS DABBY GUIDE
  // ==========================================
  Widget _buildAutonomousDabbyGuide(BuildContext context) {
    if (_isHostPerspective) {
      return _buildGuideCard(
        title: 'How Autonomous Dabby Auto-Calling Works',
        subtitle: '100% hands-free game execution on cloud schedules',
        accentColor: AppTheme.primaryLight,
        steps: const [
          'Schedule your game with "Auto-Run with Dabby Voice" enabled.',
          'Set your desired call interval (e.g. 8 seconds) and scheduled start date & time.',
          'Share your game link or invite code with your family, group or colleagues.',
          'You DO NOT need to keep your browser, phone, or computer open! Dabby runs on autonomous AWS Cloud workers.',
          'When the clock hits the scheduled time, Dabby starts calling numbers, speaks the audio cues, verifies winning tickets, and records claims autonomously.',
        ],
        tipText: '🤖 Full autonomy: Even if the host loses network connectivity, the game progresses seamlessly for all connected players.',
        actionLabel: 'Host or Schedule a Game',
        actionIcon: Icons.add_circle_outline,
        onAction: () => context.push('/host/create'),
      );
    } else {
      return _buildGuideCard(
        title: 'Playing in Autonomous Dabby Games',
        subtitle: 'Fair, transparent and automated tambola calling',
        accentColor: AppTheme.primaryLight,
        steps: const [
          'Join the game using the host\'s invite code or direct link on any mobile or desktop browser.',
          'Select your tickets before the countdown timer reaches zero.',
          'When Dabby starts calling, listen to the speech voice and watch the live called board.',
          'Dab numbers as they are called. When you complete a pattern (Early 5, Top Line, Full Housie), tap the claim button.',
          'Dabby verifies your ticket in milliseconds on the server. If valid, your prize voucher is secured instantly!',
        ],
        tipText: '⚡ Fair play guarantee: Server-side validation guarantees zero false claims and equal chance for every player.',
        actionLabel: 'Join a Game with Invite Code',
        actionIcon: Icons.login_rounded,
        onAction: () => context.go('/join'),
      );
    }
  }

  // ==========================================
  // REUSABLE STEP CARD BUILDER
  // ==========================================
  Widget _buildGuideCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<String> steps,
    required String tipText,
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + Subtitle
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Steps list
          for (int i = 0; i < steps.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFE2E8F0),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),

          // Tip Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2236),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E3B5B)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    tipText,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFCBD5E1),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action CTA
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(actionIcon, size: 16),
              label: Text(
                actionLabel,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
