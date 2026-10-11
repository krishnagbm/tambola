import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';

/// Configuration for Dabby's autonomous game scheduling & lobby management.
class DabbyScheduleConfig {
  final DateTime scheduledAt;
  final bool isAutonomousHostEnabled;
  final double quorumPercentage;
  final int gracePeriodMinutes;
  final String lowQuorumAction; // 'AUTO_CANCEL' or 'START_ANYWAY'
  final bool autoUpgradeOnWaitlist;
  final int? quorumCount;

  const DabbyScheduleConfig({
    required this.scheduledAt,
    this.isAutonomousHostEnabled = true,
    this.quorumPercentage = 0.67,
    this.gracePeriodMinutes = 5,
    this.lowQuorumAction = 'AUTO_CANCEL',
    this.autoUpgradeOnWaitlist = true,
    this.quorumCount,
  });

  int getQuorumCount(int totalCapacity) =>
      quorumCount ?? (totalCapacity * quorumPercentage).ceil();

  Map<String, dynamic> toJson({required int plannedCapacity}) => {
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'autonomous_host_enabled': isAutonomousHostEnabled,
    'quorum_percentage': quorumPercentage,
    'quorum_count': getQuorumCount(plannedCapacity),
    'grace_period_minutes': gracePeriodMinutes,
    'low_quorum_action': lowQuorumAction,
    'auto_upgrade_on_waitlist': autoUpgradeOnWaitlist,
  };

  Map<String, dynamic> toDraftJson() => {
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'autonomous_host_enabled': isAutonomousHostEnabled,
    'quorum_percentage': quorumPercentage,
    'quorum_count': quorumCount,
    'grace_period_minutes': gracePeriodMinutes,
    'low_quorum_action': lowQuorumAction,
    'auto_upgrade_on_waitlist': autoUpgradeOnWaitlist,
  };

  factory DabbyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return DabbyScheduleConfig(
      scheduledAt: json['scheduled_at'] != null
          ? (DateTime.tryParse(json['scheduled_at'].toString())?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      isAutonomousHostEnabled: json['autonomous_host_enabled'] as bool? ?? true,
      quorumPercentage: (json['quorum_percentage'] as num?)?.toDouble() ?? 0.67,
      gracePeriodMinutes: (json['grace_period_minutes'] as num?)?.toInt() ?? 5,
      lowQuorumAction: (json['low_quorum_action'] as String?) ?? 'AUTO_CANCEL',
      autoUpgradeOnWaitlist: json['auto_upgrade_on_waitlist'] as bool? ?? true,
      quorumCount: (json['quorum_count'] as num?)?.toInt(),
    );
  }

  DabbyScheduleConfig copyWith({
    DateTime? scheduledAt,
    bool? isAutonomousHostEnabled,
    double? quorumPercentage,
    int? gracePeriodMinutes,
    String? lowQuorumAction,
    bool? autoUpgradeOnWaitlist,
  }) {
    return DabbyScheduleConfig(
      scheduledAt: scheduledAt ?? this.scheduledAt,
      isAutonomousHostEnabled: isAutonomousHostEnabled ?? this.isAutonomousHostEnabled,
      quorumPercentage: quorumPercentage ?? this.quorumPercentage,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      lowQuorumAction: lowQuorumAction ?? this.lowQuorumAction,
      autoUpgradeOnWaitlist: autoUpgradeOnWaitlist ?? this.autoUpgradeOnWaitlist,
    );
  }
}

class ScheduleDialogResult {
  final bool cleared;
  final DabbyScheduleConfig? config;

  const ScheduleDialogResult({this.cleared = false, this.config});
}

class ScheduleGameDialog extends StatefulWidget {
  final DateTime? initialDateTime;
  final DabbyScheduleConfig? initialConfig;
  final int plannedCapacity;
  final int availableCredits;

  const ScheduleGameDialog({
    super.key,
    this.initialDateTime,
    this.initialConfig,
    required this.plannedCapacity,
    required this.availableCredits,
  });

  static Future<ScheduleDialogResult?> show(
    BuildContext context, {
    DateTime? initialDateTime,
    DabbyScheduleConfig? initialConfig,
    required int plannedCapacity,
    required int availableCredits,
  }) {
    return showDialog<ScheduleDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ScheduleGameDialog(
        initialDateTime: initialDateTime,
        initialConfig: initialConfig,
        plannedCapacity: plannedCapacity,
        availableCredits: availableCredits,
      ),
    );
  }

  @override
  State<ScheduleGameDialog> createState() => _ScheduleGameDialogState();
}

class _ScheduleGameDialogState extends State<ScheduleGameDialog> {
  late DateTime _selectedDateTime;
  late bool _isAutonomousHostEnabled;
  late double _quorumPercentage;
  late int _gracePeriodMinutes;
  late String _lowQuorumAction;
  late bool _autoUpgradeOnWaitlist;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to at least 30 minutes in future if not previously set
    _selectedDateTime = widget.initialConfig?.scheduledAt ??
        widget.initialDateTime ??
        now.add(const Duration(minutes: 30));

    _isAutonomousHostEnabled = widget.initialConfig?.isAutonomousHostEnabled ?? true;
    _quorumPercentage = widget.initialConfig?.quorumPercentage ?? 0.67;
    _gracePeriodMinutes = widget.initialConfig?.gracePeriodMinutes ?? 5;
    _lowQuorumAction = widget.initialConfig?.lowQuorumAction ?? 'AUTO_CANCEL';
    _autoUpgradeOnWaitlist = widget.initialConfig?.autoUpgradeOnWaitlist ?? true;
  }

  void _applyQuickPreset(Duration offset) {
    setState(() {
      _selectedDateTime = DateTime.now().add(offset);
    });
  }

  void _applyTonight() {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 20, 0);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    setState(() => _selectedDateTime = target);
  }

  void _applyTomorrowEvening() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    setState(() {
      _selectedDateTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.secondaryColor,
            onPrimary: AppTheme.primaryDark,
            surface: AppTheme.darkCard,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.secondaryColor,
            onPrimary: AppTheme.primaryDark,
            surface: AppTheme.darkCard,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow = dt.difference(DateTime(now.year, now.month, now.day)).inDays == 1 &&
        dt.day == now.add(const Duration(days: 1)).day;

    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minuteStr $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final quorumCount = (_quorumPercentage == 0.0)
        ? 1
        : (_quorumPercentage * widget.plannedCapacity).ceil();

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            _buildHeader(),
            const Divider(color: Color(0xFF2E334D), height: 1),

            // 2. Scrollable Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section A: Date & Time Picker
                    _buildDateTimeSection(),
                    const SizedBox(height: 20),

                    // Section B: Autonomous Host Switch
                    _buildAutonomousHostToggle(),
                    const SizedBox(height: 16),

                    if (_isAutonomousHostEnabled) ...[
                      // Section C: Quorum Requirement
                      _buildQuorumSection(quorumCount),
                      const SizedBox(height: 16),

                      // Section D: Grace Buffer
                      _buildGraceBufferSection(),
                      const SizedBox(height: 16),

                      // Section E: Quorum Failure / No-show Action
                      _buildLowQuorumActionSection(),
                      const SizedBox(height: 16),

                      // Section F: Waitlist Overflow Auto-Upgrade
                      _buildAutoUpgradeSection(),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(color: Color(0xFF2E334D), height: 1),

            // 3. Footer Actions
            _buildFooterActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(
              AppAssets.dabbyMascot,
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.calendar_month_rounded,
                color: AppTheme.secondaryColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schedule Game & Autonomous Controls',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Configure start time and Dabby\'s automated lobby rules',
                  style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: AppTheme.secondaryColor),
              SizedBox(width: 6),
              Text(
                'Kickoff Date & Time',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Date & Time Buttons
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Date', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(_selectedDateTime),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.secondaryColor),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _pickTime,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Time', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 2),
                            Text(
                              _formatTime(_selectedDateTime),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.secondaryColor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick Presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPresetChip('+15 Mins', () => _applyQuickPreset(const Duration(minutes: 15))),
              _buildPresetChip('+30 Mins', () => _applyQuickPreset(const Duration(minutes: 30))),
              _buildPresetChip('+1 Hour', () => _applyQuickPreset(const Duration(hours: 1))),
              _buildPresetChip('Tonight 8 PM', _applyTonight),
              _buildPresetChip('Tomorrow 7 PM', _applyTomorrowEvening),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  Widget _buildAutonomousHostToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isAutonomousHostEnabled
            ? AppTheme.secondaryColor.withValues(alpha: 0.1)
            : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isAutonomousHostEnabled
              ? AppTheme.secondaryColor.withValues(alpha: 0.5)
              : const Color(0xFF2E334D),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.smart_toy_rounded, color: AppTheme.secondaryColor, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🤖 Dabby Autonomous Host (Auto-Pilot)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Dabby greets guests, checks quorum, and kicks off game automatically.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAutonomousHostEnabled,
            activeColor: AppTheme.secondaryColor,
            onChanged: (val) => setState(() => _isAutonomousHostEnabled = val),
          ),
        ],
      ),
    );
  }

  Widget _buildQuorumSection(int quorumCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.groups_rounded, size: 16, color: AppTheme.accentSuccess),
                  SizedBox(width: 6),
                  Text(
                    'Minimum Quorum to Start',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _quorumPercentage == 0.0
                      ? 'Any player count'
                      : '$quorumCount of ${widget.plannedCapacity} Players (${(_quorumPercentage * 100).toInt()}%)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentSuccess,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Game won\'t start until this minimum number of players check into the lobby.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),

          // Presets
          Row(
            children: [
              _buildQuorumChip('50%', 0.50),
              const SizedBox(width: 6),
              _buildQuorumChip('67% (Recommended)', 0.67),
              const SizedBox(width: 6),
              _buildQuorumChip('75%', 0.75),
              const SizedBox(width: 6),
              _buildQuorumChip('100%', 1.00),
              const SizedBox(width: 6),
              _buildQuorumChip('Any', 0.0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuorumChip(String label, double value) {
    final isSelected = (_quorumPercentage - value).abs() < 0.02;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _quorumPercentage = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentSuccess.withValues(alpha: 0.2) : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.accentSuccess : const Color(0xFF334155),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? AppTheme.accentSuccess : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGraceBufferSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.hourglass_bottom_rounded, size: 16, color: AppTheme.secondaryColor),
                  SizedBox(width: 6),
                  Text(
                    'Latecomer Grace Buffer',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Text(
                'Wait $_gracePeriodMinutes Mins',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'If quorum is not met at kickoff time, Dabby broadcasts an announcement to waiting guests and waits this buffer.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              _buildGraceChip(3, '3 Mins'),
              const SizedBox(width: 8),
              _buildGraceChip(5, '5 Mins (Default)'),
              const SizedBox(width: 8),
              _buildGraceChip(10, '10 Mins'),
              const SizedBox(width: 8),
              _buildGraceChip(15, '15 Mins'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGraceChip(int minutes, String label) {
    final isSelected = _gracePeriodMinutes == minutes;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gracePeriodMinutes = minutes),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.secondaryColor.withValues(alpha: 0.2) : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.secondaryColor : const Color(0xFF334155),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? AppTheme.secondaryColor : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLowQuorumActionSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: AppTheme.accentWarning),
              SizedBox(width: 6),
              Text(
                'Quorum Not Reached Policy',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'If quorum still isn\'t met after extended wait:',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),

          _buildPolicyRadio(
            key: 'AUTO_CANCEL',
            title: 'Alert Organizer & Auto-Cancel (Refunds Credits)',
            subtitle: 'Dabby emails/notifies you. If no response after 10m, cancels party and refunds all credits.',
          ),
          const SizedBox(height: 6),
          _buildPolicyRadio(
            key: 'START_ANYWAY',
            title: 'Start Anyway with Current Players',
            subtitle: 'Dabby begins the game regardless of how many guests arrived.',
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyRadio({required String key, required String title, required String subtitle}) {
    final isSelected = _lowQuorumAction == key;
    return InkWell(
      onTap: () => setState(() => _lowQuorumAction = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondaryColor.withValues(alpha: 0.12) : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.secondaryColor : const Color(0xFF334155),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 16,
              color: isSelected ? AppTheme.secondaryColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoUpgradeSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _autoUpgradeOnWaitlist
            ? AppTheme.primaryColor.withValues(alpha: 0.1)
            : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _autoUpgradeOnWaitlist
              ? AppTheme.primaryColor.withValues(alpha: 0.5)
              : const Color(0xFF2E334D),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.upgrade_rounded, color: AppTheme.secondaryColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Waitlist Overflow Auto-Upgrade',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 2),
                const Text(
                  'If more players join than planned, Dabby automatically upgrades capacity to admit them (if credit balance allows).',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0), height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wallet Balance: ${widget.availableCredits} Credits',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoUpgradeOnWaitlist,
            activeColor: AppTheme.secondaryColor,
            onChanged: (val) => setState(() => _autoUpgradeOnWaitlist = val),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.initialDateTime != null || widget.initialConfig != null)
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const ScheduleDialogResult(cleared: true),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentDanger,
              ),
              child: const Text('Clear Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ),
          ElevatedButton.icon(
            onPressed: () {
              final config = DabbyScheduleConfig(
                scheduledAt: _selectedDateTime,
                isAutonomousHostEnabled: _isAutonomousHostEnabled,
                quorumPercentage: _quorumPercentage,
                gracePeriodMinutes: _gracePeriodMinutes,
                lowQuorumAction: _lowQuorumAction,
                autoUpgradeOnWaitlist: _autoUpgradeOnWaitlist,
              );
              Navigator.pop(
                context,
                ScheduleDialogResult(config: config),
              );
            },
            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: const Text('Save & Apply Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: AppTheme.primaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
