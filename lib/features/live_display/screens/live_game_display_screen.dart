import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
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
