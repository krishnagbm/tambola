import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/admin_reports_repository.dart';

class CreatePromotionalSeriesDialog extends ConsumerStatefulWidget {
  final List<dynamic> existingGames;

  const CreatePromotionalSeriesDialog({
    super.key,
    required this.existingGames,
  });

  @override
  ConsumerState<CreatePromotionalSeriesDialog> createState() =>
      _CreatePromotionalSeriesDialogState();
}

enum PromoTemplate {
  festivalMega, // 250 Players, $35 Pool, Dabby Auto
  corporateTeam, // 500+ Players, $35 Pool, Corporate Team Sizing, Dabby Auto
  standardPromo, // 50 Players, $15 Pool, Dabby Auto
  customClone, // Clone from selected past game
}

class EventSlotItem {
  String name;
  DateTime dateTime;

  EventSlotItem({required this.name, required this.dateTime});
}

class _CreatePromotionalSeriesDialogState
    extends ConsumerState<CreatePromotionalSeriesDialog> {
  // Mode: Single vs Multi
  bool _isMultiSeries = false;

  // Selected Template
  PromoTemplate _selectedTemplate = PromoTemplate.festivalMega;
  Map<String, dynamic>? _selectedClonedGame;

  // Single event controllers
  late TextEditingController _singleNameController;
  late DateTime _singleDateTime;

  // Multi series controllers
  late TextEditingController _multiBaseTitleController;
  final List<EventSlotItem> _multiSlots = [];

  // Configuration options
  int _capacity = 250;
  late TextEditingController _customCapacityController;
  double _budget = 35.0;
  final bool _isPubliclyVisible = true;
  final bool _autonomousHost = true;

  // State
  bool _isSubmitting = false;
  String? _errorMessage;
  List<Map<String, dynamic>>? _createdResults;

  @override
  void initState() {
    super.initState();

    _customCapacityController = TextEditingController(text: '$_capacity');

    // Default to upcoming Saturday at 11:30 AM EST (EDT / UTC-4)
    final now = DateTime.now();
    final daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
    final nextSaturdayDate = now.add(Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday));
    _singleDateTime = DateTime(
      nextSaturdayDate.year,
      nextSaturdayDate.month,
      nextSaturdayDate.day,
      11,
      30,
    );

    _singleNameController = TextEditingController(text: 'DabHousie Saturday 🏆');
    _multiBaseTitleController = TextEditingController(text: 'DabHousie Weekend League 🏆');

    // Default 2 weekend slots for multi
    _multiSlots.add(EventSlotItem(
      name: 'DabHousie Saturday League 🏆',
      dateTime: _singleDateTime,
    ));
    _multiSlots.add(EventSlotItem(
      name: 'DabHousie Sunday Dhamaka 🏆',
      dateTime: _singleDateTime.add(const Duration(days: 1)),
    ));

    // If cloning, default to most recent game with prizes
    if (widget.existingGames.isNotEmpty) {
      _selectedClonedGame = widget.existingGames.first as Map<String, dynamic>?;
    }
  }

  @override
  void dispose() {
    _singleNameController.dispose();
    _multiBaseTitleController.dispose();
    _customCapacityController.dispose();
    super.dispose();
  }

  void _onTemplateChanged(PromoTemplate t) {
    setState(() {
      _selectedTemplate = t;
      if (t == PromoTemplate.festivalMega) {
        _capacity = 250;
        _budget = 35.0;
      } else if (t == PromoTemplate.corporateTeam) {
        _capacity = 500;
        _budget = 35.0;
        if (!_isMultiSeries && _singleNameController.text.contains('Saturday')) {
          _singleNameController.text = 'DabHousie Corporate Gala 🏆';
        }
      } else if (t == PromoTemplate.standardPromo) {
        _capacity = 50;
        _budget = 15.0;
      } else if (t == PromoTemplate.customClone && _selectedClonedGame != null) {
        _capacity = (_selectedClonedGame!['initial_funded_capacity'] as int?) ?? 250;
        _budget = ((_selectedClonedGame!['total_prize_budget'] as num?)?.toDouble()) ?? 35.0;
      }
      _customCapacityController.text = '$_capacity';
    });
  }

  // Quick preset helpers
  void _setSinglePreset(int daysFromNow, int hour, int minute, String suggestedName) {
    final now = DateTime.now();
    final target = now.add(Duration(days: daysFromNow));
    setState(() {
      _singleDateTime = DateTime(target.year, target.month, target.day, hour, minute);
      _singleNameController.text = suggestedName;
    });
  }

  void _applyMultiWeekendPreset() {
    final now = DateTime.now();
    final daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
    final sat = now.add(Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday));
    final satTime = DateTime(sat.year, sat.month, sat.day, 11, 30);
    final sunTime = satTime.add(const Duration(days: 1));

    setState(() {
      _multiSlots.clear();
      _multiSlots.add(EventSlotItem(name: '${_multiBaseTitleController.text} - Day 1 (Sat)', dateTime: satTime));
      _multiSlots.add(EventSlotItem(name: '${_multiBaseTitleController.text} - Day 2 (Sun)', dateTime: sunTime));
    });
  }

  void _applyMulti4DayFestivalPreset() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day + 1, 11, 30);

    setState(() {
      _multiSlots.clear();
      for (int i = 0; i < 4; i++) {
        final slotTime = base.add(Duration(days: i));
        final dateLabel = DateFormat('MMM d').format(slotTime);
        _multiSlots.add(EventSlotItem(
          name: '${_multiBaseTitleController.text} - Day ${i + 1} ($dateLabel)',
          dateTime: slotTime,
        ));
      }
    });
  }

  Future<void> _pickDateTime(bool isSingle, [int? slotIndex]) async {
    final initialDate = isSingle ? _singleDateTime : _multiSlots[slotIndex!].dateTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.secondaryColor,
            surface: AppTheme.darkCard,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.secondaryColor,
            surface: AppTheme.darkCard,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isSingle) {
        _singleDateTime = combined;
      } else {
        _multiSlots[slotIndex!].dateTime = combined;
      }
    });
  }

  Future<void> _handleCreate() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final List<Map<String, dynamic>> gamesPayload = [];

      // Determine prize gifts & prizes config
      Map<String, dynamic> prizeGiftsConfig;
      List<dynamic> prizesConfig;

      if (_selectedTemplate == PromoTemplate.customClone && _selectedClonedGame != null) {
        prizeGiftsConfig = Map<String, dynamic>.from(
          (_selectedClonedGame!['prize_gifts_config'] as Map?) ??
              AdminReportsRepository.getDefaultPromotionalPrizeGifts(),
        );
        prizesConfig = List<dynamic>.from(
          (_selectedClonedGame!['prizes_config'] as List?) ??
              ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'],
        );
      } else {
        prizeGiftsConfig = AdminReportsRepository.getDefaultPromotionalPrizeGifts();
        prizesConfig = [
          'EARLY_FIVE',
          'TOP_LINE',
          'MIDDLE_LINE',
          'BOTTOM_LINE',
          'FOUR_CORNERS',
          'FULL_HOUSE',
        ];
      }

      final tierId = AdminReportsRepository.resolveTierIdForCapacity(_capacity);

      if (!_isMultiSeries) {
        // Single game
        final name = _singleNameController.text.trim();
        if (name.isEmpty) {
          throw Exception('Please provide an event title.');
        }

        final giftsCopy = Map<String, dynamic>.from(prizeGiftsConfig);
        final utcIso = _singleDateTime.toUtc().toIso8601String();

        if (_autonomousHost) {
          giftsCopy['_dabby_orchestration'] = {
            'autonomous_host_enabled': true,
            'scheduled_at': utcIso,
            'low_quorum_action': 'AUTO_CANCEL',
            'quorum_count': 1,
            'quorum_percentage': 0,
            'grace_period_minutes': 3,
            'auto_upgrade_on_waitlist': true,
          };
        }

        gamesPayload.add({
          'name': name,
          'capacity': _capacity,
          'planned_capacity_tier_id': tierId,
          'scheduled_at': utcIso,
          'prizes_config': prizesConfig,
          'prize_gifts_config': giftsCopy,
          'total_prize_budget': _budget,
          'is_publicly_visible': _isPubliclyVisible,
          'minor_prize_policy': 'ONE_LINE_PLUS_BONUS',
        });
      } else {
        // Multi series
        if (_multiSlots.isEmpty) {
          throw Exception('Please add at least one event slot for the series.');
        }

        for (final slot in _multiSlots) {
          final name = slot.name.trim();
          if (name.isEmpty) {
            throw Exception('Each slot must have an event title.');
          }

          final giftsCopy = Map<String, dynamic>.from(prizeGiftsConfig);
          final utcIso = slot.dateTime.toUtc().toIso8601String();

          if (_autonomousHost) {
            giftsCopy['_dabby_orchestration'] = {
              'autonomous_host_enabled': true,
              'scheduled_at': utcIso,
              'low_quorum_action': 'AUTO_CANCEL',
              'quorum_count': 1,
              'quorum_percentage': 0,
              'grace_period_minutes': 3,
              'auto_upgrade_on_waitlist': true,
            };
          }

          gamesPayload.add({
            'name': name,
            'capacity': _capacity,
            'planned_capacity_tier_id': tierId,
            'scheduled_at': utcIso,
            'prizes_config': prizesConfig,
            'prize_gifts_config': giftsCopy,
            'total_prize_budget': _budget,
            'is_publicly_visible': _isPubliclyVisible,
            'minor_prize_policy': 'ONE_LINE_PLUS_BONUS',
          });
        }
      }

      // Execute batch creation
      final res = await ref.read(adminReportsRepositoryProvider).createPromotionalGameBatch(
            games: gamesPayload,
            incrementBrandOffers: true,
          );

      if (res['success'] == true) {
        final list = List<Map<String, dynamic>>.from(res['created_games'] ?? []);
        ref.invalidate(adminReportsOverviewProvider);
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _createdResults = list;
          });
        }
      } else {
        throw Exception(res['error'] ?? 'Batch creation returned failure status.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _copyDirectJoinLink(String code, String name) {
    final link = 'https://www.dabhousie.com/#/join/$code';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.accentSuccess,
        content: Text('🔗 Copied direct join link for $name!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyCorporateInvite(Map<String, dynamic> game) {
    final name = game['name'] ?? 'Corporate Team Event 🏆';
    final code = game['invite_code'] ?? '';
    final capacity = game['initial_funded_capacity'] ?? _capacity;
    final sched = game['scheduled_at'] != null ? DateTime.tryParse(game['scheduled_at']) : null;
    final timeStr = sched != null ? Formatters.formatDate(sched) : 'TBD';
    final link = 'https://www.dabhousie.com/#/join/$code';

    final text = '''
🏢 Join our Corporate Team Game on DabHousie!

🏆 Event: $name
📅 Scheduled Time: $timeStr
👥 Team Capacity: $capacity Players

👉 Direct Join Link:
$link

🔑 Room Code: $code

• Instant play in any browser (mobile, tablet, or laptop).
• No app install or registration required.
• Live interactive ticket daubing with automated host calling & prize recognition!
''';

    Clipboard.setData(ClipboardData(text: text.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.accentSuccess,
        content: Text('🏢 Corporate team invite copied to clipboard! Ready to paste in Slack/Teams/Email.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _shareOnWhatsApp(Map<String, dynamic> game) async {
    final name = game['name'] ?? 'DabHousie Live Event 🏆';
    final code = game['invite_code'] ?? '';
    final link = 'https://www.dabhousie.com/#/join/$code';
    final sched = game['scheduled_at'] != null ? DateTime.tryParse(game['scheduled_at']) : null;
    final timeStr = sched != null ? Formatters.formatDate(sched) : '';

    final text = '🎉 Join our game on DabHousie: $name\n📅 Time: $timeStr\n👉 Tap link to join: $link\n🔑 Code: $code';
    final uri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _openInBrowser(String code) async {
    final uri = Uri.parse('https://www.dabhousie.com/#/join/$code');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _copyAllMarketingMessage() {
    if (_createdResults == null || _createdResults!.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('🎉 DabHousie Official Promotional Events & Live Schedule!\n');

    for (final g in _createdResults!) {
      final name = g['name'] ?? 'DabHousie Live Event 🏆';
      final code = g['invite_code'] ?? '';
      final sched = g['scheduled_at'] != null ? DateTime.tryParse(g['scheduled_at']) : null;
      final timeStr = sched != null ? Formatters.formatDate(sched) : 'TBD';
      final link = 'https://www.dabhousie.com/#/join/$code';

      buffer.writeln('🏆 $name');
      buffer.writeln('📅 Time: $timeStr');
      buffer.writeln('🔑 Code: $code');
      buffer.writeln('👉 Tap to join free: $link\n');
    }

    buffer.writeln('📺 Watch live gameplay highlights: https://youtu.be/z3U-tmRc-ec');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.accentSuccess,
        content: Text('📋 Full marketing announcement copied to clipboard!'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF334155), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _createdResults != null ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  // ==========================================
  // FORM VIEW
  // ==========================================
  Widget _buildFormView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.celebration, color: Color(0xFFF59E0B), size: 24),
                SizedBox(width: 10),
                Text(
                  'Create Promotional Event / Series',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Batch schedule official DabHousie sponsored events with automated Dabby host calling & brand prize vouchers.',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.3),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mode Toggle (Single vs Multi Series)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isMultiSeries = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !_isMultiSeries ? AppTheme.secondaryColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'Single Event',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: !_isMultiSeries ? Colors.black : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isMultiSeries = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _isMultiSeries ? AppTheme.secondaryColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'Multi-Game Series / Batch 🏆',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isMultiSeries ? Colors.black : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Template Selector Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16192E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.workspace_premium, color: Color(0xFFF59E0B), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'SELECT PRIZE & LINEUP TEMPLATE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Template Option 1: Festival / Saturday League
                      _buildTemplateOption(
                        PromoTemplate.festivalMega,
                        title: 'Festival / Saturday League 🏆 (Recommended)',
                        subtitle: '250 Players • \$35 Pool (\$5 DABFREE5 x 5 + \$10 DABFREE10) + \$1 Bounty • Dabby Auto',
                      ),
                      const SizedBox(height: 6),

                      // Template Option 2: Corporate Team Building
                      _buildTemplateOption(
                        PromoTemplate.corporateTeam,
                        title: 'Corporate Event / Team Building 🏢',
                        subtitle: '500+ Players • Scaled On-Demand Ticket Engine • Dabby Auto Host • Instant Direct Room Link',
                      ),
                      const SizedBox(height: 6),

                      // Template Option 3: Standard Promo
                      _buildTemplateOption(
                        PromoTemplate.standardPromo,
                        title: 'Standard Promotional Game 🎯',
                        subtitle: '50 Players • \$15 Pool (\$5 Early-5 + \$10 Full House) • Dabby Auto',
                      ),
                      const SizedBox(height: 6),

                      // Template Option 4: Clone from Past Game
                      _buildTemplateOption(
                        PromoTemplate.customClone,
                        title: 'Clone Past Game Setup 📋',
                        subtitle: 'Copy exact prize gifts & capacity from any past game',
                      ),

                      if (_selectedTemplate == PromoTemplate.customClone &&
                          widget.existingGames.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: _selectedClonedGame,
                          dropdownColor: const Color(0xFF1E2238),
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Select Past Game to Clone',
                            labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: widget.existingGames.map((g) {
                            final m = g as Map<String, dynamic>;
                            final name = m['name'] ?? 'Unnamed';
                            final code = m['invite_code'] ?? '';
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: m,
                              child: Text('$name ($code)', overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedClonedGame = val;
                                _capacity = (val['initial_funded_capacity'] as int?) ?? 250;
                                _customCapacityController.text = '$_capacity';
                                _budget = ((val['total_prize_budget'] as num?)?.toDouble()) ?? 35.0;
                              });
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Dedicated Player Capacity & Corporate Sizing Card
                _buildCapacitySection(),
                const SizedBox(height: 16),

                // Schedule & Titles section
                if (!_isMultiSeries) _buildSingleEventSection() else _buildMultiSeriesSection(),

                const SizedBox(height: 16),

                // Safeguards & Feature Badges
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: AppTheme.accentSuccess, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Capacity: $_capacity Players (${_capacity > 1000 ? "Coliseum / Global" : (_capacity > 500 ? "Enterprise Arena" : (_capacity > 250 ? "Corporate League" : "Mega Fair-Play"))} Tier • Zero Host Deductions)',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.smart_toy_outlined, color: AppTheme.secondaryColor, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Autonomous Dabby Calling enabled (Starts at scheduled time without host presence)',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined, color: Color(0xFF38BDF8), size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Public Listing enabled (Auto-listed for players to pre-register on Recent Games)',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentDanger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppTheme.accentDanger, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF475569)),
                ),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch, size: 16),
                label: Text(
                  _isSubmitting
                      ? 'Creating Game(s)...'
                      : (!_isMultiSeries
                          ? 'Create Event Now'
                          : 'Create ${_multiSlots.length} Games Batch 🚀'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Template radio option helper
  Widget _buildTemplateOption(
    PromoTemplate template, {
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedTemplate == template;
    return GestureDetector(
      onTap: () => _onTemplateChanged(template),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.secondaryColor : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.secondaryColor : const Color(0xFF64748B),
                  width: isSelected ? 5 : 2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CAPACITY & CORPORATE SIZING BUILDER
  // ==========================================
  Widget _buildCapacitySection() {
    final isCorporate = _capacity > 250;
    final isEnterprise = _capacity > 500;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16192E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorporate ? const Color(0xFFF59E0B) : const Color(0xFF2E334D),
          width: isCorporate ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isCorporate ? Icons.business : Icons.groups_rounded,
                    color: isCorporate ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PLAYER CAPACITY & CORPORATE SIZING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCorporate
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                      : const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCorporate
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                        : const Color(0xFF0284C7).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '$_capacity Players',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isCorporate ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preset Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildCapacityChip(50, '50 (Standard)'),
              _buildCapacityChip(100, '100 (Club)'),
              _buildCapacityChip(250, '250 (Festival Mega)'),
              _buildCapacityChip(500, '500 (Corporate 🏢)'),
              _buildCapacityChip(1000, '1,000 (Enterprise 🏛️)'),
            ],
          ),
          const SizedBox(height: 12),

          // Custom number input box
          TextField(
            controller: _customCapacityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Custom Participant Capacity (Seats)',
              labelStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              hintText: 'Enter any number (e.g. 350, 500, 750, 1200)',
              filled: true,
              fillColor: const Color(0xFF0F172A),
              prefixIcon: const Icon(Icons.people_outline, size: 16, color: Color(0xFF94A3B8)),
              suffixText: 'Seats',
              suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (val) {
              final n = int.tryParse(val.trim());
              if (n != null && n > 0) {
                setState(() {
                  _capacity = n.clamp(5, 5000);
                });
              }
            },
          ),
          const SizedBox(height: 8),

          // Dynamic explanation
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isCorporate
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                    : const Color(0xFF334155),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCorporate ? Icons.verified : Icons.info_outline,
                  color: isCorporate ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEnterprise
                        ? '🏛️ Enterprise Cluster Tier: $_capacity players supported. On-demand ticket generation guarantees instant link access without server bottlenecks.'
                        : (isCorporate
                            ? '🏢 Corporate League Tier: $_capacity players supported. Instant shareable room link with automated Dabby calling.'
                            : '⚡ Standard/Festival Tier: $_capacity players supported with zero host deductions.'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isCorporate ? const Color(0xFFFDE68A) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityChip(int value, String label) {
    final isSelected = _capacity == value;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.black : const Color(0xFFCBD5E1),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFF59E0B),
      backgroundColor: const Color(0xFF0F172A),
      side: BorderSide(
        color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF334155),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _capacity = value;
            _customCapacityController.text = '$value';
          });
        }
      },
    );
  }

  // Single event form section
  Widget _buildSingleEventSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EVENT NAME',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _singleNameController,
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. DabHousie Saturday 🏆',
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),

        const Text(
          'SCHEDULED TIME (EST / LOCAL)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 6),

        InkWell(
          onTap: () => _pickDateTime(true),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppTheme.secondaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMM d, y • h:mm a').format(_singleDateTime),
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const Icon(Icons.edit, size: 15, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Quick Preset Chips
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ActionChip(
              backgroundColor: const Color(0xFF1E2238),
              side: const BorderSide(color: Color(0xFF334155)),
              label: const Text('Next Saturday (11:30 AM EST)', style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
              onPressed: () {
                final now = DateTime.now();
                final daysUntil = (DateTime.saturday - now.weekday + 7) % 7;
                _setSinglePreset(daysUntil == 0 ? 7 : daysUntil, 11, 30, 'DabHousie Saturday 🏆');
              },
            ),
            ActionChip(
              backgroundColor: const Color(0xFF1E2238),
              side: const BorderSide(color: Color(0xFF334155)),
              label: const Text('Next Sunday (11:30 AM EST)', style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
              onPressed: () {
                final now = DateTime.now();
                final daysUntil = (DateTime.sunday - now.weekday + 7) % 7;
                _setSinglePreset(daysUntil == 0 ? 7 : daysUntil, 11, 30, 'DabHousie Sunday Dhamaka 🏆');
              },
            ),
          ],
        ),
      ],
    );
  }

  // Multi series form section
  Widget _buildMultiSeriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SERIES BASE TITLE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _multiBaseTitleController,
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. DabHousie Weekend League 🏆',
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),

        // Quick Batch Presets
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ActionChip(
              backgroundColor: const Color(0xFF1E2238),
              side: const BorderSide(color: Color(0xFF334155)),
              avatar: const Icon(Icons.flash_on, size: 13, color: Color(0xFFF59E0B)),
              label: const Text('Weekend Set (Sat + Sun 11:30 AM)', style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
              onPressed: _applyMultiWeekendPreset,
            ),
            ActionChip(
              backgroundColor: const Color(0xFF1E2238),
              side: const BorderSide(color: Color(0xFF334155)),
              avatar: const Icon(Icons.festival, size: 13, color: Color(0xFF38BDF8)),
              label: const Text('4-Day Festival Set (Daily 11:30 AM)', style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1))),
              onPressed: _applyMulti4DayFestivalPreset,
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SERIES GAMES TO CREATE (${_multiSlots.length})',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF94A3B8),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final lastTime = _multiSlots.isNotEmpty
                    ? _multiSlots.last.dateTime.add(const Duration(days: 1))
                    : DateTime.now().add(const Duration(days: 1));
                setState(() {
                  _multiSlots.add(EventSlotItem(
                    name: '${_multiBaseTitleController.text} - Event ${_multiSlots.length + 1} 🏆',
                    dateTime: lastTime,
                  ));
                });
              },
              icon: const Icon(Icons.add, size: 14, color: AppTheme.secondaryColor),
              label: const Text('Add Slot', style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryColor)),
            ),
          ],
        ),

        // Slots List
        ..._multiSlots.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _pickDateTime(false, index),
                        child: Text(
                          DateFormat('EEE, MMM d, y • h:mm a').format(item.dateTime),
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF38BDF8)),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_calendar, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Change Date/Time',
                  onPressed: () => _pickDateTime(false, index),
                ),
                if (_multiSlots.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.accentDanger),
                    tooltip: 'Remove Slot',
                    onPressed: () => setState(() => _multiSlots.removeAt(index)),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // SUCCESS VIEW
  // ==========================================
  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentSuccess.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppTheme.accentSuccess, size: 40),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '🎉 ${_createdResults!.length} Promotional Event(s) Created!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 4),
        const Text(
          'All events are live, registered with Dabby autonomous calling, and open for player reservations.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: ListView.separated(
            itemCount: _createdResults!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final g = _createdResults![i];
              final name = g['name'] ?? 'Promotional Game';
              final code = g['invite_code'] ?? '';
              final sched = g['scheduled_at'] != null ? DateTime.tryParse(g['scheduled_at']) : null;
              final link = 'https://www.dabhousie.com/#/join/$code';

              final cap = g['initial_funded_capacity'] ?? _capacity;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cap > 250 ? const Color(0xFFF59E0B) : const Color(0xFF334155),
                    width: cap > 250 ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (sched != null) ...[
                          Text(
                            '📅 ${Formatters.formatDate(sched)}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: cap > 250
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                : const Color(0xFF0284C7).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: cap > 250
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                  : const Color(0xFF0284C7).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            cap > 250 ? '🏢 $cap Corporate Seats' : '👥 $cap Seats',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cap > 250 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Direct Link Bar with 1-Tap Copy & Open
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16192E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2E334D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 14, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              link,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14, color: Colors.white),
                            tooltip: 'Copy Link',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _copyDirectJoinLink(code, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 14, color: Colors.white70),
                            tooltip: 'Open Room in New Tab',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _openInBrowser(code),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Immediate Sharing Actions for Teams & Corporations
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _copyCorporateInvite(g),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF047857),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.business_center, size: 13),
                          label: const Text('🏢 Copy Corporate Invite'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _copyDirectJoinLink(code, name),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.link, size: 13),
                          label: const Text('🔗 Copy Link'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _shareOnWhatsApp(g),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF25D366),
                            side: const BorderSide(color: Color(0xFF25D366)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.chat, size: 13),
                          label: const Text('📲 WhatsApp'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Marketing Announcement Button
        ElevatedButton.icon(
          onPressed: _copyAllMarketingMessage,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.share, size: 16),
          label: const Text(
            '📋 Copy Full Marketing Announcement',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),

        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: const BorderSide(color: Color(0xFF475569)),
          ),
          child: const Text('Done & Return to Dashboard', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
