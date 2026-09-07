import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_game.dart';
import '../../../providers/app_providers.dart';

class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key});

  @override
  ConsumerState<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends ConsumerState<CreateGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Family Tambola Night');
  int _selectedCapacity = 10;
  String? _selectedTierId;
  bool _isLoading = false;

  DateTime? _scheduledDateTime;

  final Map<String, bool> _prizes = {
    'EARLY_FIVE': true,
    'TOP_LINE': true,
    'MIDDLE_LINE': true,
    'BOTTOM_LINE': true,
    'FOUR_CORNERS': true,
    'FULL_HOUSE': true,
    'SECOND_FULL_HOUSE': false,
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final activePrizes = _prizes.entries.where((e) => e.value).map((e) => e.key).toList();
      final gameRepo = ref.read(gameRepositoryProvider);

      final game = await gameRepo.createGame(
        name: _nameController.text.trim(),
        plannedCapacity: _selectedCapacity,
        plannedCapacityTierId: _selectedTierId,
        scheduledAt: _scheduledDateTime,
        prizesConfig: activePrizes,
      );

      if (!mounted) return;
      _showSuccessDialog(game);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleShare(MptGame game) async {
    final link = 'https://tambola.digitalappstudio.com/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play Tambola in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap to join or download the app:\n$link';
    await Share.share(text, subject: 'Join Tambola Game: ${game.name}');
  }

  void _showSuccessDialog(MptGame game) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.accentSuccess),
            SizedBox(width: 8),
            Text('Game Created! 🎉', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Game: ${game.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('Share this Invite Code with your players:', style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    game.inviteCode,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2, color: AppTheme.secondaryColor),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, color: AppTheme.primaryLight),
                        tooltip: 'Copy Code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: game.inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite code copied to clipboard!')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: AppTheme.secondaryColor),
                        tooltip: 'Share Invite',
                        onPressed: () => _handleShare(game),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Initial Funded Capacity: ${game.fundedCapacity} Seats (Overflow players will automatically join the Waiting List).',
              style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _handleShare(game),
            icon: const Icon(Icons.share, size: 16, color: AppTheme.secondaryColor),
            label: const Text('Share Link', style: TextStyle(color: AppTheme.secondaryColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/admin-lobby/${game.id}');
            },
            child: const Text('Open Organizer Lobby'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Game'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Game / Event Name',
                  hintText: 'e.g. Diwalli Party Tambola',
                  prefixIcon: Icon(Icons.celebration),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter game name' : null,
              ),
              const SizedBox(height: 20),

              _buildSchedulePicker(),
              const SizedBox(height: 24),

              const Text('Expected Group Size (Capacity)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Choose initial seats. If more join, they will be queued in the Waiting List.',
                style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
              ),
              const SizedBox(height: 12),
              _buildCapacitySelector(),
              const SizedBox(height: 24),

              const Text('Winning Patterns / Prizes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: _prizes.keys.map((key) {
                      String label;
                      switch (key) {
                        case 'EARLY_FIVE':
                          label = 'Early 5 (Jaldi 5)';
                          break;
                        case 'TOP_LINE':
                          label = 'Top Line';
                          break;
                        case 'MIDDLE_LINE':
                          label = 'Middle Line';
                          break;
                        case 'BOTTOM_LINE':
                          label = 'Bottom Line';
                          break;
                        case 'FOUR_CORNERS':
                          label = 'Four Corners';
                          break;
                        case 'FULL_HOUSE':
                          label = 'Full House (First Winner)';
                          break;
                        case 'SECOND_FULL_HOUSE':
                          label = 'Second Full House';
                          break;
                        default:
                          label = key;
                      }
                      return CheckboxListTile(
                        title: Text(label, style: const TextStyle(fontSize: 14)),
                        value: _prizes[key],
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) => setState(() => _prizes[key] = val ?? false),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleCreate,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Game & Generate Invite Code', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapacitySelector() {
    final tiersState = ref.watch(capacityTiersProvider);

    return tiersState.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => _buildStaticCapacityOptions(),
      data: (tiers) {
        if (tiers.isEmpty) return _buildStaticCapacityOptions();

        // If not set yet, pick the first tier
        if (_selectedTierId == null && tiers.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedTierId = tiers.first.id;
                _selectedCapacity = tiers.first.maxPlayers;
              });
            }
          });
        }

        return Column(
          children: tiers.map((tier) {
            final isSelected = _selectedTierId == tier.id || (_selectedTierId == null && _selectedCapacity == tier.maxPlayers);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() {
                  _selectedTierId = tier.id;
                  _selectedCapacity = tier.maxPlayers;
                }),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFF2E334D),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tier.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(
                            '${tier.minPlayers}–${tier.maxPlayers} Players • ${tier.creditsRequired} Credits',
                            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryColor),
                          ),
                        ],
                      ),
                      Radio<String>(
                        value: tier.id,
                        groupValue: _selectedTierId ?? tiers.first.id,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) => setState(() {
                          _selectedTierId = val;
                          _selectedCapacity = tier.maxPlayers;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStaticCapacityOptions() {
    final options = [
      {'capacity': 10, 'label': '1–10 Players', 'desc': 'Starter / Free Trial • 10 Credits'},
      {'capacity': 25, 'label': '11–25 Players', 'desc': 'Small Party • 25 Credits'},
      {'capacity': 50, 'label': '26–50 Players', 'desc': 'Standard Event • 50 Credits'},
      {'capacity': 100, 'label': '51–100 Players', 'desc': 'Large Gala • 100 Credits'},
      {'capacity': 250, 'label': '101–250 Players', 'desc': 'Mega Event • 250 Credits'},
    ];

    return Column(
      children: options.map((opt) {
        final cap = opt['capacity'] as int;
        final isSelected = _selectedCapacity == cap;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _selectedCapacity = cap),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryColor : const Color(0xFF2E334D),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opt['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(opt['desc'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
                    ],
                  ),
                  Radio<int>(
                    value: cap,
                    groupValue: _selectedCapacity,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _selectedCapacity = val!),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSchedulePicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _scheduledDateTime != null ? AppTheme.secondaryColor : const Color(0xFF2E334D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month,
                size: 20,
                color: _scheduledDateTime != null ? AppTheme.secondaryColor : const Color(0xFFA0AEC0),
              ),
              const SizedBox(width: 8),
              const Text(
                'Scheduled Game Time (Optional)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _scheduledDateTime == null
                ? 'Game will be playable immediately when you start the lobby.'
                : 'Scheduled for: ${_formatDateTime(_scheduledDateTime!)}',
            style: TextStyle(
              fontSize: 13,
              color: _scheduledDateTime != null ? AppTheme.secondaryColor : const Color(0xFFA0AEC0),
              fontWeight: _scheduledDateTime != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickScheduleDateTime,
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(_scheduledDateTime == null ? 'Set Date & Time' : 'Change Time'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondaryColor,
                  side: const BorderSide(color: AppTheme.secondaryColor),
                ),
              ),
              if (_scheduledDateTime != null) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => setState(() => _scheduledDateTime = null),
                  child: const Text('Clear (Start Now)', style: TextStyle(color: AppTheme.accentDanger)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minuteStr $ampm';

    if (isToday) {
      return 'Today at $timeStr';
    }
    return '${dt.day}/${dt.month}/${dt.year} at $timeStr';
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledDateTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: AppTheme.darkCard,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _scheduledDateTime != null
          ? TimeOfDay.fromDateTime(_scheduledDateTime!)
          : TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: AppTheme.darkCard,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime == null || !mounted) return;

    setState(() {
      _scheduledDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }
}

