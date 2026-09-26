import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class PlayerLobbyShowcasePlayer extends StatefulWidget {
  const PlayerLobbyShowcasePlayer({super.key});

  @override
  State<PlayerLobbyShowcasePlayer> createState() =>
      _PlayerLobbyShowcasePlayerState();
}

class _PlayerLobbyShowcasePlayerState extends State<PlayerLobbyShowcasePlayer>
    with SingleTickerProviderStateMixin {
  static const int _scenesPerTab = 4;
  static const Duration _sceneDuration = Duration(milliseconds: 4800);
  static const Duration _tickInterval = Duration(milliseconds: 60);

  int _activeTab = 0; // 0 = How to Play, 1 = How to Host
  int _sceneIndex = 0; // 0..3 within current tab
  bool _isPlaying = true;
  double _sceneProgress = 0.0;
  Timer? _timer;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final stepIncrement =
        _tickInterval.inMilliseconds / _sceneDuration.inMilliseconds;
    _timer = Timer.periodic(_tickInterval, (_) {
      if (!_isPlaying || !mounted) return;
      setState(() {
        _sceneProgress += stepIncrement;
        if (_sceneProgress >= 1.0) {
          _sceneProgress = 0.0;
          if (_sceneIndex < _scenesPerTab - 1) {
            _sceneIndex++;
          } else {
            _sceneIndex = 0;
            _activeTab = (_activeTab + 1) % 2;
          }
        }
      });
    });
  }

  void _selectTab(int tab) {
    setState(() {
      _activeTab = tab;
      _sceneIndex = 0;
      _sceneProgress = 0.0;
    });
  }

  void _selectScene(int index) {
    setState(() {
      _sceneIndex = index.clamp(0, _scenesPerTab - 1);
      _sceneProgress = 0.0;
    });
  }

  void _nextScene() {
    setState(() {
      _sceneProgress = 0.0;
      if (_sceneIndex < _scenesPerTab - 1) {
        _sceneIndex++;
      } else {
        _sceneIndex = 0;
        _activeTab = (_activeTab + 1) % 2;
      }
    });
  }

  void _prevScene() {
    setState(() {
      _sceneProgress = 0.0;
      if (_sceneIndex > 0) {
        _sceneIndex--;
      } else {
        _activeTab = (_activeTab + 1) % 2;
        _sceneIndex = _scenesPerTab - 1;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryLight.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header & Mode Switcher
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_fill_rounded,
                            size: 13,
                            color: AppTheme.secondaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'WHILE YOU WAIT • INTERACTIVE GUIDE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _isPlaying ? '● AUTO-PLAY' : '❚❚ PAUSED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _isPlaying
                            ? AppTheme.accentSuccess
                            : const Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 2-Tab Segmented Switcher (A: How to Play, B: Host Your Own)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          index: 0,
                          icon: Icons.confirmation_number_rounded,
                          label: 'How to Play & Win',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildTabButton(
                          index: 1,
                          icon: Icons.rocket_launch_rounded,
                          label: 'Host a Game Like This',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          //Segmented Story Progress Bars (Instagram/YouTube Story style)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(_scenesPerTab, (i) {
                final double fill = i < _sceneIndex
                    ? 1.0
                    : (i == _sceneIndex ? _sceneProgress : 0.0);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectScene(i),
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i < _scenesPerTab - 1 ? 6 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _activeTab == 0
                                ? AppTheme.secondaryColor
                                : AppTheme.accentSuccess,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 10),

          // Animated Video Stage
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 235),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _activeTab == 0
                      ? [const Color(0xFF131C31), const Color(0xFF1E1B4B)]
                      : [const Color(0xFF0F292A), const Color(0xFF172554)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: KeyedSubtree(
                  key: ValueKey('tab_${_activeTab}_scene_$_sceneIndex'),
                  child: _activeTab == 0
                      ? _buildHowToPlayScene(_sceneIndex)
                      : _buildHowToHostScene(_sceneIndex),
                ),
              ),
            ),
          ),

          // Video Controls Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _isPlaying = !_isPlaying),
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: AppTheme.secondaryColor,
                    size: 28,
                  ),
                  tooltip: _isPlaying ? 'Pause walkthrough' : 'Play walkthrough',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: _prevScene,
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  tooltip: 'Previous step',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: _nextScene,
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  tooltip: 'Next step',
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _activeTab == 0
                        ? 'Part 1 of 2: Playing Your Ticket (Step ${_sceneIndex + 1}/$_scenesPerTab)'
                        : 'Part 2 of 2: Hosting on DabHousie (Step ${_sceneIndex + 1}/$_scenesPerTab)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _activeTab == index;
    return GestureDetector(
      onTap: () => _selectTab(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (index == 0
                  ? AppTheme.primaryColor
                  : const Color(0xFF059669))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB A: HOW TO PLAY & WIN (4 SCENES)
  // ===========================================================================
  Widget _buildHowToPlayScene(int scene) {
    switch (scene) {
      case 0:
        return _buildSceneLayout(
          badge: 'STEP 1 • AUTO TICKET & LIVE CALLS',
          title: 'Your 3×9 Ticket Opens Automatically When Game Starts',
          subtitle:
              'As soon as the host starts the session, your screen switches to your unique 15-number ticket. Watch the live ball calls or tap the speaker icon 🔊 for voice announcements!',
          visual: _buildAnimatedCallerVisual(),
        );
      case 1:
        return _buildSceneLayout(
          badge: 'STEP 2 • MANUAL DABBING',
          title: 'Tap Called Numbers on Your Ticket to Dab Them',
          subtitle:
              'Tickets do NOT auto-mark! Listen carefully and tap each called number on your 3×9 grid to place a glowing gold dab chip.',
          visual: _buildAnimatedTicketDabVisual(),
        );
      case 2:
        return _buildSceneLayout(
          badge: 'STEP 3 • CLAIMING PRIZES (NO BOGEYS!)',
          title: 'Complete a Pattern & Tap "Claim Prize" Immediately',
          subtitle:
              'Win Early 5 (Jaldi 5), Top/Middle/Bottom Lines, Four Corners, or Full House! Only mark numbers that have actually been called to avoid a Bogey.',
          visual: _buildAnimatedPatternsVisual(),
        );
      default:
        return _buildSceneLayout(
          badge: 'STEP 4 • INSTANT SERVER VERIFICATION',
          title: 'Milliseconds Verification & Digital Gift Vouchers',
          subtitle:
              'DabHousie verifies your ticket automatically—no reading numbers over Zoom! Winners unlock digital brand gift vouchers & shareable Winner Certificates.',
          visual: _buildAnimatedWinnerRewardVisual(),
        );
    }
  }

  // ===========================================================================
  // TAB B: HOW TO HOST YOUR OWN GAME (4 SCENES)
  // ===========================================================================
  Widget _buildHowToHostScene(int scene) {
    switch (scene) {
      case 0:
        return _buildSceneLayout(
          badge: 'HOSTING • STEP 1',
          title: 'Host Your Own Game: 1–5 Players is 100% FREE!',
          subtitle:
              'Planning a family game night, kitty party, festival gala, or Friday office icebreaker? Host 1–5 players free anytime, or up to 250 players from just \$2.',
          visual: _buildHostPricingVisual(),
        );
      case 1:
        return _buildSceneLayout(
          badge: 'HOSTING • STEP 2',
          title: 'Zero App Downloads — Share a 6-Digit Code or QR Scan',
          subtitle:
              'Your guests join in 5 seconds right in their mobile browser (Safari/Chrome). No app store installs and no guest sign-ups required.',
          visual: _buildHostInviteVisual(),
        );
      case 2:
        return _buildSceneLayout(
          badge: 'HOSTING • STEP 3',
          title: 'Big-Screen TV / Zoom Broadcast & Custom Logo Branding',
          subtitle:
              'Cast the studio-grade 1–90 Live Board to a TV or share on Zoom/Teams. Corporate hosts can display their company logo on every ticket via DVAA™.',
          visual: _buildHostBroadcastVisual(),
        );
      default:
        return _buildSceneLayout(
          badge: 'HOSTING • STEP 4',
          title: 'Attach Global Brand Gift Vouchers & Launch in 60s',
          subtitle:
              'Reward winners with digital vouchers in \$, ₹, £, €, or A\$. Want to explore how hosting works while you wait?',
          visual: _buildHostCtaVisual(),
        );
    }
  }

  Widget _buildSceneLayout({
    required String badge,
    required String title,
    required String subtitle,
    required Widget visual,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              badge,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.secondaryColor,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFCBD5E1),
                height: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        visual,
      ],
    );
  }

  // --- Visual 1: Animated Caller Balls ---
  Widget _buildAnimatedCallerVisual() {
    final activeBallIndex = (_sceneProgress * 4).floor().clamp(0, 3);
    const balls = [42, 7, 78, 19];
    const phrases = [
      '"Number 42!"',
      '"Lucky Seven — 7!"',
      '"Seventy-Eight — 78!"',
      '"Nineteen — 19!"',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.06).animate(
              _pulseController,
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFDE047), Color(0xFFD97706)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.45),
                    blurRadius: 12,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '${balls[activeBallIndex]}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 15,
                      color: AppTheme.secondaryColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LIVE CALLER: ${phrases[activeBallIndex]}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: List.generate(balls.length, (i) {
                    final isCalled = i <= activeBallIndex;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isCalled
                            ? AppTheme.primaryLight.withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isCalled
                              ? AppTheme.primaryLight
                              : Colors.white12,
                        ),
                      ),
                      child: Text(
                        '#${balls[i]}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isCalled ? Colors.white : Colors.white38,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Visual 2: Animated 3x9 Mini Ticket Dabbing ---
  Widget _buildAnimatedTicketDabVisual() {
    final step = (_sceneProgress * 4).floor().clamp(0, 3);
    final cells = <int?>[4, null, 23, 35, null, 58, null, 72, 88];
    final dabbedUpTo = step + 1; // progressively dabs cells
    int nonNullCount = 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: cells.map((val) {
              bool isDabbed = false;
              if (val != null) {
                nonNullCount++;
                isDabbed = nonNullCount <= dabbedUpTo;
              }
              return Expanded(
                child: Container(
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isDabbed
                        ? const Color(0xFF1E3A8A)
                        : (val != null
                            ? const Color(0xFF1E293B)
                            : const Color(0xFF0F172A)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDabbed
                          ? AppTheme.secondaryColor
                          : Colors.white12,
                      width: isDabbed ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: val == null
                      ? const SizedBox.shrink()
                      : Container(
                          width: 24,
                          height: 24,
                          decoration: isDabbed
                              ? const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.secondaryColor,
                                )
                              : null,
                          alignment: Alignment.center,
                          child: Text(
                            '$val',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: isDabbed ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.touch_app_rounded,
                size: 15,
                color: AppTheme.secondaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Tapped $dabbedUpTo of 5 numbers in Top Line!',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Visual 3: Winning Patterns & Claim Button ---
  Widget _buildAnimatedPatternsVisual() {
    final activeIdx = (_sceneProgress * 4).floor().clamp(0, 3);
    const patterns = [
      ('🎯 Early 5 (Jaldi 5)', 'First 5 called numbers anywhere'),
      ('📏 Top / Mid / Bottom Line', 'All 5 numbers in any horizontal row'),
      ('📐 Four Corners', '1st & last numbers of Top & Bottom rows'),
      ('🏆 Full House', 'All 15 numbers on your ticket!'),
    ];
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(patterns.length, (i) {
              final isCurrent = i == activeIdx;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent ? AppTheme.accentSuccess : Colors.white12,
                  ),
                ),
                child: Text(
                  patterns[i].$1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isCurrent ? Colors.white : Colors.white70,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.05).animate(
            _pulseController,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.accentSuccess,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentSuccess.withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_rounded, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'CLAIM!',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Visual 4: Winner Verification & Digital Voucher ---
  Widget _buildAnimatedWinnerRewardVisual() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.secondaryColor.withValues(alpha: 0.18),
            AppTheme.accentSuccess.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.5),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.verified_rounded,
            color: AppTheme.accentSuccess,
            size: 32,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLAIM APPROVED IN 0.02s! 🎉',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '🎁 Digital Gift Voucher & Shareable Winner Certificate Unlocked',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Host Visual 1: Free & Paid Packs ---
  Widget _buildHostPricingVisual() {
    const tiers = [
      ('🎁 1–5 Players', 'FREE (\$0)', true),
      ('15 Players', '\$2 Pack', false),
      ('25 Players', '\$5 Pack', false),
      ('100–250p', '\$10–\$20', false),
    ];
    return Row(
      children: tiers.map((t) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: t.$3
                  ? AppTheme.accentSuccess.withValues(alpha: 0.22)
                  : Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: t.$3 ? AppTheme.accentSuccess : Colors.white12,
                width: t.$3 ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  t.$1,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 3),
                Text(
                  t.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: t.$3
                        ? const Color(0xFF6EE7B7)
                        : AppTheme.secondaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Host Visual 2: QR & 6-Digit Invite ---
  Widget _buildHostInviteVisual() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 32, color: Colors.white),
              SizedBox(height: 2),
              Text(
                'Scan QR',
                style: TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
            ],
          ),
          Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white38),
          Column(
            children: [
              Icon(
                Icons.pin_outlined,
                size: 30,
                color: AppTheme.secondaryColor,
              ),
              SizedBox(height: 2),
              Text(
                '6-Digit Code',
                style: TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
            ],
          ),
          Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white38),
          Column(
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                size: 30,
                color: AppTheme.accentSuccess,
              ),
              SizedBox(height: 2),
              Text(
                'Instant Web Ticket',
                style: TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Host Visual 3: TV Broadcast + Corporate DVAA ---
  Widget _buildHostBroadcastVisual() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.tv_rounded, size: 32, color: AppTheme.secondaryColor),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live 1–90 Projector Board + Voice Caller',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '🏢 DVAA™ Verified Corporate Logo on Every Ticket',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Host Visual 4: Learn More / Host After Game CTA ---
  Widget _buildHostCtaVisual() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              launchUrl(
                Uri.parse('https://www.dabhousie.com/how-it-works.html'),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('See How Hosting Works ↗'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.secondaryColor,
              side: const BorderSide(color: AppTheme.secondaryColor),
              padding: const EdgeInsets.symmetric(vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
