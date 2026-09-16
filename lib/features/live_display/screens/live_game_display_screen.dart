import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/mpt_claim.dart';
import '../../../providers/app_providers.dart';

class LiveGameDisplayScreen extends ConsumerStatefulWidget {
  final String gameId;

  const LiveGameDisplayScreen({super.key, required this.gameId});

  @override
  ConsumerState<LiveGameDisplayScreen> createState() => _LiveGameDisplayScreenState();
}

class _LiveGameDisplayScreenState extends ConsumerState<LiveGameDisplayScreen> {
  int _lastAnnouncedSeq = 0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;
  }

  void _showCastDialog() {
    final liveUrl = LiveDisplayHelper.getLiveDisplayUrl(widget.gameId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cast_connected, color: AppTheme.secondaryColor, size: 26),
            SizedBox(width: 10),
            Text('Stream to TV / Projector', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Display this real-time game board on your TV, Projector, or secondary monitor using any of the methods below:',
                  style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1), height: 1.4),
                ),
                const SizedBox(height: 16),

                // QR Code & Direct Link Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: liveUrl,
                          version: QrVersions.auto,
                          size: 130.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Scan QR with Phone or Smart TV Remote',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F36),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2E334D)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                liveUrl,
                                style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                              tooltip: 'Copy Link',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: liveUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Live Display URL copied to clipboard! 📋'),
                                    backgroundColor: AppTheme.accentSuccess,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Method 1: Browser Native Cast
                _buildCastOption(
                  icon: Icons.cast,
                  title: '1. Browser Cast (Chromecast & Smart TVs)',
                  description: 'In Chrome or Edge, click the browser menu (⋮) → Cast... → choose your Chromecast, Google TV, or Smart TV.',
                ),
                const SizedBox(height: 10),

                // Method 2: Apple AirPlay
                _buildCastOption(
                  icon: Icons.airplay,
                  title: '2. Apple AirPlay (Apple TV & Mac/iOS)',
                  description: 'Open Control Center on your Mac or iPhone/iPad → Screen Mirroring → choose Apple TV or AirPlay 2 Smart TV.',
                ),
                const SizedBox(height: 10),

                // Method 3: Direct Smart TV Browser
                _buildCastOption(
                  icon: Icons.tv,
                  title: '3. Smart TV Browser (Samsung, LG, FireTV)',
                  description: 'Open the built-in browser app on your TV and type the link above or scan the QR code.',
                ),
                const SizedBox(height: 10),

                // Method 4: HDMI Cable / 2nd Monitor
                _buildCastOption(
                  icon: Icons.monitor,
                  title: '4. HDMI / Dual Monitor Projection',
                  description: 'Drag this browser tab over to your TV or Projector screen, then press F11 for edge-to-edge fullscreen.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildCastOption({required IconData icon, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.secondaryColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));

    // Announce new number if sequence increased
    calledStream.whenData((calledNumbers) {
      if (calledNumbers.isNotEmpty && calledNumbers.length > _lastAnnouncedSeq) {
        _lastAnnouncedSeq = calledNumbers.length;
        final latestNum = calledNumbers.last.number;
        TambolaAudioCaller().announceNumber(latestNum);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppAssets.horizontalLogo, height: 28, fit: BoxFit.contain),
            const SizedBox(width: 10),
            const Text('• Projector View', style: TextStyle(fontSize: 15, color: Color(0xFFA0AEC0))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cast, color: AppTheme.secondaryColor),
            tooltip: 'Stream & Cast to TV / Projector',
            onPressed: _showCastDialog,
          ),
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: _isMuted ? Colors.grey : AppTheme.secondaryColor),
            tooltip: _isMuted ? 'Unmute Audio Caller' : 'Mute Audio Caller',
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
                TambolaAudioCaller().isMuted = _isMuted;
              });
            },
          ),
        ],
      ),
      body: gameStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (game) {
          return calledStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (calledNumbers) {
              final latest = calledNumbers.isNotEmpty ? calledNumbers.last.number : null;
              final calledSet = calledNumbers.map((e) => e.number).toSet();

              return LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildBoardGrid(calledSet),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  children: [
                                    _buildCurrentBallHero(latest, calledNumbers.length),
                                    const SizedBox(height: 16),
                                    Expanded(child: _buildLiveWinnersPanel(claimsStream)),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildCurrentBallHero(latest, calledNumbers.length),
                                const SizedBox(height: 16),
                                _buildBoardGrid(calledSet),
                                const SizedBox(height: 16),
                                _buildLiveWinnersPanel(claimsStream),
                              ],
                            ),
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCurrentBallHero(int? latest, int totalCalled) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryColor.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          const Text('NOW CALLING', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white70)),
          const SizedBox(height: 8),
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                latest != null ? '$latest' : 'READY',
                style: TextStyle(
                  fontSize: latest != null ? 54 : 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$totalCalled / 90 Numbers Called',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardGrid(Set<int> calledSet) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Called Numbers Board', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 90,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1.1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled ? AppTheme.accentSuccess : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isCalled ? AppTheme.accentSuccess : const Color(0xFF2E334D)),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isCalled ? Colors.white : const Color(0xFFA0AEC0),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveWinnersPanel(AsyncValue<List<MptClaim>> claimsStream) {
    return Card(
      color: AppTheme.darkSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 20),
                SizedBox(width: 8),
                Text('Winners Board', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(color: Color(0xFF2E334D)),
            claimsStream.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Unable to load winners'),
              data: (claims) {
                final winners = claims.where((c) => c.status == 'APPROVED').toList();
                if (winners.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No winners declared yet.', style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                  );
                }

                return Column(
                  children: winners.map((w) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              Formatters.getAvatarEmoji(w.userAvatar),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Formatters.formatPrizeName(w.prizeType),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                ),
                                Text(
                                  'Won by: ${w.userName ?? "Player"}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.secondaryColor),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Formatters.formatShortDate(w.submittedAt),
                            style: const TextStyle(fontSize: 10, color: Color(0xFFA0AEC0)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
