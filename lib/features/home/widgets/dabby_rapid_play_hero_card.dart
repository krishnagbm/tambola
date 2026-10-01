import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';

class DabbyRapidPlayHeroCard extends StatefulWidget {
  const DabbyRapidPlayHeroCard({super.key});

  @override
  State<DabbyRapidPlayHeroCard> createState() => _DabbyRapidPlayHeroCardState();
}

class _DabbyRapidPlayHeroCardState extends State<DabbyRapidPlayHeroCard>
    with SingleTickerProviderStateMixin {
  static const double _callDurationSec = 5.0;
  static const int _maxConsecutiveMisses = 5;

  static const List<List<int>> _colRanges = [
    [1, 9],
    [10, 19],
    [20, 29],
    [30, 39],
    [40, 49],
    [50, 59],
    [60, 69],
    [70, 79],
    [80, 90],
  ];

  List<List<int?>> _ticket = [
    List.filled(9, null),
    List.filled(9, null),
    List.filled(9, null),
  ];
  final Set<int> _ticketNums = <int>{};
  final Set<int> _dabbedNums = <int>{};
  final List<int> _calledHistory = <int>[];
  List<int> _uncalledPool = <int>[];

  int? _currentBall;
  int _score = 0;
  int _consecutiveMisses = 0;
  bool _isGameOver = false;
  String _gameOverReason = '';
  bool _isFullHouseWon = false;

  Timer? _countdownTimer;
  double _timeLeftSec = _callDurationSec;
  late AnimationController _ballPopController;
  late Animation<double> _ballPopScale;

  String? _feedbackText;
  Color _feedbackColor = Colors.white;
  Timer? _feedbackTimer;

  int _gameCode = 577873;

  @override
  void initState() {
    super.initState();
    _ballPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ballPopScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.25), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _ballPopController, curve: Curves.easeOutBack),
    );

    _startNewGame();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _feedbackTimer?.cancel();
    _ballPopController.dispose();
    super.dispose();
  }

  void _startNewGame() {
    _countdownTimer?.cancel();
    final random = Random();
    _gameCode = 100000 + random.nextInt(900000);
    _dabbedNums.clear();
    _calledHistory.clear();
    _score = 0;
    _consecutiveMisses = 0;
    _isGameOver = false;
    _gameOverReason = '';
    _isFullHouseWon = false;

    _uncalledPool = List.generate(90, (i) => i + 1)..shuffle(random);
    _generateAuthenticTicket();
    _callNextBall();
  }

  void _generateAuthenticTicket() {
    final random = Random();
    _ticket = [
      List.filled(9, null),
      List.filled(9, null),
      List.filled(9, null),
    ];
    _ticketNums.clear();

    const configurations = [
      [3, 6, 0],
      [4, 4, 1],
      [5, 2, 2],
      [3, 3, 2],
    ];
    final config = configurations[random.nextInt(configurations.length)];
    final num1s = config[0];
    final num2s = config[1];
    final num3s = config[2];

    final colCounts = <int>[];
    for (int i = 0; i < num1s; i++) {
      colCounts.add(1);
    }
    for (int i = 0; i < num2s; i++) {
      colCounts.add(2);
    }
    for (int i = 0; i < num3s; i++) {
      colCounts.add(3);
    }
    colCounts.shuffle(random);

    final colNumbers = <List<int>>[];
    for (int c = 0; c < 9; c++) {
      final range = _colRanges[c];
      final pool = List.generate(range[1] - range[0] + 1, (i) => range[0] + i)..shuffle(random);
      final picked = pool.take(colCounts[c]).toList()..sort();
      colNumbers.add(picked);
      _ticketNums.addAll(picked);
    }

    // Place columns with 3 numbers
    for (int c = 0; c < 9; c++) {
      if (colCounts[c] == 3) {
        _ticket[0][c] = colNumbers[c][0];
        _ticket[1][c] = colNumbers[c][1];
        _ticket[2][c] = colNumbers[c][2];
      }
    }

    // Place columns with 2 numbers
    for (int c = 0; c < 9; c++) {
      if (colCounts[c] == 2) {
        final rowIdxs = [0, 1, 2]..sort((r1, r2) {
          final count1 = _ticket[r1].where((x) => x != null).length;
          final count2 = _ticket[r2].where((x) => x != null).length;
          return count1.compareTo(count2);
        });
        final rA = min(rowIdxs[0], rowIdxs[1]);
        final rB = max(rowIdxs[0], rowIdxs[1]);
        _ticket[rA][c] = colNumbers[c][0];
        _ticket[rB][c] = colNumbers[c][1];
      }
    }

    // Place columns with 1 number
    for (int c = 0; c < 9; c++) {
      if (colCounts[c] == 1) {
        final rowIdxs = [0, 1, 2]..sort((r1, r2) {
          final count1 = _ticket[r1].where((x) => x != null).length;
          final count2 = _ticket[r2].where((x) => x != null).length;
          return count1.compareTo(count2);
        });
        _ticket[rowIdxs[0]][c] = colNumbers[c][0];
      }
    }
  }

  void _callNextBall() {
    if (_isFullHouseWon || _isGameOver) return;
    if (_uncalledPool.isEmpty) {
      _triggerGameOver('All 90 numbers called!');
      return;
    }

    final random = Random();
    final remainingTicketNums = _ticketNums.difference(_dabbedNums).difference(_calledHistory.toSet()).toList();

    int pick;
    if (remainingTicketNums.isNotEmpty && random.nextDouble() < 0.75) {
      pick = remainingTicketNums[random.nextInt(remainingTicketNums.length)];
      _uncalledPool.remove(pick);
    } else {
      pick = _uncalledPool.removeLast();
    }

    setState(() {
      _currentBall = pick;
      _calledHistory.add(pick);
      _timeLeftSec = _callDurationSec;
    });

    _ballPopController.forward(from: 0.0);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    const tickMs = 50;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _timeLeftSec -= (tickMs / 1000.0);
        if (_timeLeftSec <= 0) {
          _timeLeftSec = 0;
          timer.cancel();
          _onTimerExpired();
        }
      });
    });
  }

  void _onTimerExpired() {
    if (_isFullHouseWon || _isGameOver) return;
    _consecutiveMisses++;
    if (_consecutiveMisses >= _maxConsecutiveMisses) {
      _triggerGameOver('You missed $_maxConsecutiveMisses calls in a row without dabbing.');
      return;
    }

    if (_ticketNums.contains(_currentBall) && !_dabbedNums.contains(_currentBall)) {
      _showFeedback('⏰ MISSED CALL!', const Color(0xFFEF4444));
    }

    _callNextBall();
  }

  void _triggerGameOver(String reason) {
    _countdownTimer?.cancel();
    setState(() {
      _isGameOver = true;
      _gameOverReason = reason;
    });
  }

  void _onCellTapped(int number) {
    if (_isGameOver || _isFullHouseWon) return;
    if (_dabbedNums.contains(number)) return;

    if (number == _currentBall) {
      // Perfect Dab!
      setState(() {
        _dabbedNums.add(number);
        _score += 100;
        _consecutiveMisses = 0;
      });
      _showFeedback('⚡ PERFECT DAB! +100', const Color(0xFF10B981));
      _checkVictory();
      if (!_isFullHouseWon) {
        _callNextBall();
      }
    } else if (_calledHistory.contains(number)) {
      // Delayed Dab!
      setState(() {
        _dabbedNums.add(number);
        _score += 50;
        _consecutiveMisses = 0;
      });
      _showFeedback('⏱️ DELAYED DAB! +50', const Color(0xFFFACC15));
      _checkVictory();
    } else {
      // Not called yet
      _showFeedback('⏳ NOT CALLED YET!', const Color(0xFFF87171));
    }
  }

  void _checkVictory() {
    if (_dabbedNums.length >= 15) {
      _countdownTimer?.cancel();
      setState(() {
        _isFullHouseWon = true;
      });
    }
  }

  void _showFeedback(String msg, Color color) {
    _feedbackTimer?.cancel();
    setState(() {
      _feedbackText = msg;
      _feedbackColor = color;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _feedbackText = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;
    final isOnTicket = _currentBall != null && _ticketNums.contains(_currentBall) && !_dabbedNums.contains(_currentBall);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090D1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnTicket
              ? const Color(0xFFEF4444)
              : AppTheme.secondaryColor.withValues(alpha: 0.5),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOnTicket ? const Color(0xFFEF4444) : AppTheme.primaryColor).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(isWide ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. TOP CALLER & PRESSURE BAR
          _buildTopCallerBar(isWide, isOnTicket),
          const SizedBox(height: 12),

          // 2. MASCOT 3x9 TICKET BANNER PLAYGROUND (1536 x 1024 Aspect Ratio)
          AspectRatio(
            aspectRatio: 1536 / 1024,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // High-Res Background Image
                  Image.asset(
                    AppAssets.dabbyTicketBanner,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Text(
                          'Dabby Mascot Playground',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),

                  // Dynamic Game Code Overlay
                  Positioned(
                    top: 14,
                    right: 18,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Text(
                        'Game Code: $_gameCode',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),

                  // Active 3x9 Grid Overlay matching empty ticket template coordinates
                  // left: 23.43%, top: 31.84%, width: 73.05%, height: 39.45%
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final gridLeft = constraints.maxWidth * 0.2343;
                      final gridTop = constraints.maxHeight * 0.3184;
                      final gridWidth = constraints.maxWidth * 0.7305;
                      final gridHeight = constraints.maxHeight * 0.3945;

                      return Positioned(
                        left: gridLeft,
                        top: gridTop,
                        width: gridWidth,
                        height: gridHeight,
                        child: _buildGridCells(gridWidth, gridHeight),
                      );
                    },
                  ),

                  // Feedback Float
                  if (_feedbackText != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _feedbackColor, width: 1.5),
                        ),
                        child: Text(
                          _feedbackText!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _feedbackColor,
                          ),
                        ),
                      ),
                    ),

                  // Victory Banner
                  if (_isFullHouseWon)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEAB308), Color(0xFFCA8A04)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '🏆 FULL HOUSE VICTORY! 🎉',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF451A03),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'All 15 numbers dabbed with Dabby!',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF451A03),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _startNewGame,
                              icon: const Icon(Icons.replay_rounded, size: 18),
                              label: const Text('Play Another Round'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF451A03),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Game Over / Inactivity Banner
                  if (_isGameOver)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444), width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black87,
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '⏰ GAME OVER',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFF87171),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _gameOverReason,
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _startNewGame,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Play Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.black,
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCallerBar(bool isWide, bool isOnTicket) {
    final progress = (_timeLeftSec / _callDurationSec).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnTicket ? const Color(0xFFEF4444) : Colors.white12,
          width: isOnTicket ? 1.8 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Current Called Ball
          ScaleTransition(
            scale: _ballPopScale,
            child: Container(
              width: isWide ? 56 : 46,
              height: isWide ? 56 : 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F), Color(0xFF8B0000)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFD32F2F),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _currentBall != null ? '$_currentBall' : '--',
                  style: TextStyle(
                    fontSize: isWide ? 26 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Caller Message & Prompt
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOnTicket
                            ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                            : AppTheme.secondaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isOnTicket ? '🔥 ON YOUR TICKET' : 'BALL CALLED',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: isOnTicket ? const Color(0xFFF87171) : AppTheme.secondaryColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_score Pts • ${_dabbedNums.length}/15',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isGameOver
                      ? 'Game Over'
                      : (isOnTicket
                          ? 'DAB $_currentBall NOW!'
                          : 'Dabby called $_currentBall • Scan your ticket!'),
                  style: TextStyle(
                    fontSize: isWide ? 15 : 13,
                    fontWeight: FontWeight.w900,
                    color: isOnTicket ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),

          // Countdown Ring
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _timeLeftSec <= 2.0 ? const Color(0xFFEF4444) : const Color(0xFFFACC15),
                  ),
                ),
                Text(
                  '${_timeLeftSec.ceil()}s',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // New Game / Reset
          IconButton(
            tooltip: 'New Ticket',
            onPressed: _startNewGame,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCells(double width, double height) {
    final cellWidth = width / 9.0;
    final cellHeight = height / 3.0;

    return Stack(
      children: [
        for (int r = 0; r < 3; r++)
          for (int c = 0; c < 9; c++)
            if (_ticket[r][c] != null)
              Positioned(
                left: c * cellWidth,
                top: r * cellHeight,
                width: cellWidth,
                height: cellHeight,
                child: _buildCell(_ticket[r][c]!),
              ),
      ],
    );
  }

  Widget _buildCell(int num) {
    final isDabbed = _dabbedNums.contains(num);
    final isCurrent = num == _currentBall && !isDabbed;

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: InkWell(
        onTap: () => _onCellTapped(num),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: isDabbed
                ? const Color(0xFFFACC15).withValues(alpha: 0.88)
                : (isCurrent ? const Color(0xFFEF4444).withValues(alpha: 0.35) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: isCurrent
                ? Border.all(color: const Color(0xFFEF4444), width: 2)
                : null,
          ),
          child: Center(
            child: Text(
              '$num',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: isDabbed ? const Color(0xFF0F172A) : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
