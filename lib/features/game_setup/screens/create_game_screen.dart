import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_game.dart';
import '../../../providers/app_providers.dart';
import '../../home/widgets/corporate_inquiry_dialog.dart';

class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key});

  @override
  ConsumerState<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends ConsumerState<CreateGameScreen> {
  static const _suggestedNames = [
    'Friday DebHousie Fiesta 🎊',
    'Weekend Housefull Mania 🏠',
    'Bollywood Housie Night 🎬',
    'Diwali DebHousie Dhamaka 🪔',
    'Friends & Family Blast 🎉',
    'Super Sunday DebHousie Party 🌟',
    'Office Chai & DebHousie Break ☕',
    'Monsoon DebHousie Carnival 🌧️',
    'Kitty Party DebHousie Bonanza 💃',
    'Late Night DebHousie Chill 🌙',
    'Festive DebHousie Extravaganza 🎈',
    'Clubhouse DebHousie League 🏆',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  int _selectedCapacity = 5;
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
  void initState() {
    super.initState();
    final initialName = (List<String>.from(_suggestedNames)..shuffle()).first;
    _nameController = TextEditingController(text: initialName);
  }

  void _randomizeName() {
    final nextName = (List<String>.from(_suggestedNames)..shuffle()).first;
    _nameController.text = nextName;
  }

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
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DebHousie in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap to join or download the app:\n$link';
    await Share.share(text, subject: 'Join DebHousie: ${game.name}');
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
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              AppAssets.horizontalLogo,
              height: 38,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
              ),
              child: const Text(
                'Host',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, size: 18, color: AppTheme.secondaryColor),
            label: const Text('Home', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBrandingHeader(),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Game / Event Name',
                      hintText: 'e.g. Diwali Party DebHousie',
                      prefixIcon: const Icon(Icons.celebration),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.casino_outlined, color: AppTheme.secondaryColor),
                        tooltip: 'Shuffle Event Name',
                        onPressed: _randomizeName,
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Please enter game name' : null,
                  ),
                  const SizedBox(height: 20),

                  _buildSchedulePicker(),
                  const SizedBox(height: 24),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isTwoColumn = constraints.maxWidth >= 640;
                      if (isTwoColumn) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildGroupSizeSection(),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildWinningPatternsSection(includeCreateButton: true),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildGroupSizeSection(),
                            const SizedBox(height: 24),
                            _buildWinningPatternsSection(includeCreateButton: false),
                            const SizedBox(height: 24),
                            _buildCreateButton(),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Expected Group Size (Capacity)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose initial seats. If more join, they will be queued in the Waiting List.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFFA0AEC0)),
        ),
        const SizedBox(height: 12),
        _buildCapacitySelector(),
      ],
    );
  }

  Widget _buildWinningPatternsSection({bool includeCreateButton = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Winning Patterns / Prizes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select winning combinations eligible for prize claims during the game.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFFA0AEC0)),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
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
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  title: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  value: _prizes[key],
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) => setState(() => _prizes[key] = val ?? false),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Custom Winning Patterns Enterprise Callout
        InkWell(
          onTap: () => CorporateInquiryDialog.show(context, initialTopic: 'Custom Winning Patterns'),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentPartyPurple.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPartyPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentPartyPurple, size: 16),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Need Custom Patterns?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                      SizedBox(height: 2),
                      Text('Star, Breakfast, King/Queen & custom rules →', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.accentPartyPurple, size: 12),
              ],
            ),
          ),
        ),
        if (includeCreateButton) ...[
          const SizedBox(height: 14),
          _buildCreateButton(),
        ],
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleCreate,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 3,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rocket_launch_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Create Game & Generate Invite Code',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBrandingHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.25),
            AppTheme.darkSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5)),
            ),
            child: Image.asset(
              AppAssets.monogramDH,
              height: 36,
              width: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.celebration, color: AppTheme.secondaryColor, size: 30),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'DebHousie Game Setup',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text('✨', style: TextStyle(fontSize: 15)),
                  ],
                ),
                SizedBox(height: 3),
                Text(
                  'Host your live Housie party, set seats, and invite players.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
        ],
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
          children: [
            ...tiers.map((tier) {
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
                              tier.creditsRequired == 0
                                  ? '${tier.minPlayers}–${tier.maxPlayers} Players • Always Free (0 Credits)'
                                  : '${tier.minPlayers}–${tier.maxPlayers} Players • ${tier.creditsRequired} Credits',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: tier.creditsRequired == 0 ? FontWeight.bold : FontWeight.normal,
                                color: tier.creditsRequired == 0 ? AppTheme.accentSuccess : AppTheme.secondaryColor,
                              ),
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
            }),
            const SizedBox(height: 4),
            _buildMegaXCallout(),
          ],
        );
      },
    );
  }

  Widget _buildStaticCapacityOptions() {
    final options = [
      {'capacity': 5, 'label': '1–5 Players', 'desc': 'Family Pack • Always Free (0 Credits)'},
      {'capacity': 15, 'label': '6–15 Players', 'desc': 'Small Party • 50 Credits'},
      {'capacity': 25, 'label': '16–25 Players', 'desc': 'Standard Event • 100 Credits'},
      {'capacity': 100, 'label': '26–100 Players', 'desc': 'Large Gala • 250 Credits'},
      {'capacity': 250, 'label': '101–250 Players', 'desc': 'Mega Event • 500 Credits'},
    ];

    return Column(
      children: [
        ...options.map((opt) {
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
        }),
        const SizedBox(height: 4),
        _buildMegaXCallout(),
      ],
    );
  }

  Widget _buildMegaXCallout() {
    return InkWell(
      onTap: () => CorporateInquiryDialog.show(context, initialTopic: 'Mega-X Event (250 to 100,000+ Players)'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.corporate_fare_rounded, color: AppTheme.secondaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Planning 250 to 100K+ Players (Mega-X)?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  SizedBox(height: 2),
                  Text('Custom pricing, dedicated high-concurrency scale & corporate support →', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.secondaryColor, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _scheduledDateTime != null ? AppTheme.secondaryColor : const Color(0xFF2E334D),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isHorizontal = constraints.maxWidth >= 520;
          final infoColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 4),
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
            ],
          );

          final actionsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _pickScheduleDateTime,
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(_scheduledDateTime == null ? 'Set Date & Time' : 'Change Time'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondaryColor,
                  side: const BorderSide(color: AppTheme.secondaryColor),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              if (_scheduledDateTime != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _scheduledDateTime = null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  child: const Text('Clear', style: TextStyle(color: AppTheme.accentDanger, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          );

          if (isHorizontal) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: infoColumn),
                const SizedBox(width: 16),
                actionsRow,
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                infoColumn,
                const SizedBox(height: 12),
                actionsRow,
              ],
            );
          }
        },
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

