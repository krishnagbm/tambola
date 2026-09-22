import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_game.dart';
import '../../../providers/app_providers.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../auth/widgets/auth_dialog.dart';
import '../../home/widgets/corporate_inquiry_dialog.dart';

class CreateGameScreen extends ConsumerStatefulWidget {
  const CreateGameScreen({super.key});

  @override
  ConsumerState<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends ConsumerState<CreateGameScreen> {
  static const _suggestedNames = [
    'Friday DabHousie Fiesta 🎊',
    'Weekend Housefull Mania 🏠',
    'Bollywood Housie Night 🎬',
    'Diwali DabHousie Dhamaka 🪔',
    'Friends & Family Blast 🎉',
    'Super Sunday DabHousie Party 🌟',
    'Office Chai & DabHousie Break ☕',
    'Monsoon DabHousie Carnival 🌧️',
    'Kitty Party DabHousie Bonanza 💃',
    'Late Night DabHousie Chill 🌙',
    'Festive DabHousie Extravaganza 🎈',
    'Clubhouse DabHousie League 🏆',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _orgNameController;
  late final TextEditingController _orgLogoUrlController;
  late final TextEditingController _orgApproverEmailController;
  bool _enableOrgBranding = false;
  bool _orgVisualConfirmed = false;

  int _selectedCapacity = 5;
  String? _selectedTierId = 'ba630f87-517a-44e2-8da9-e96e235d3c36';
  bool _isPrivate = false;
  bool _isLoading = false;

  String _getPrivateCreditBreakdownText(int maxPlayers) {
    if (maxPlayers <= 5) return 'Free + 5 = 5 Credits';
    if (maxPlayers <= 15) return '15 + 5 = 20 Credits';
    if (maxPlayers <= 25) return '25 + 10 = 35 Credits';
    if (maxPlayers <= 50) return '50 + 20 = 70 Credits';
    if (maxPlayers <= 100) return '100 + 35 = 135 Credits';
    return '250 + 75 = 325 Credits';
  }

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
    _orgNameController = TextEditingController()..addListener(() => setState(() {}));
    _orgLogoUrlController = TextEditingController()..addListener(() => setState(() {}));
    _orgApproverEmailController = TextEditingController()..addListener(() => setState(() {}));
  }

  void _randomizeName() {
    final nextName = (List<String>.from(_suggestedNames)..shuffle()).first;
    _nameController.text = nextName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orgNameController.dispose();
    _orgLogoUrlController.dispose();
    _orgApproverEmailController.dispose();
    super.dispose();
  }

  bool _isDomainMatching(String logoUrl, String email) {
    if (logoUrl.isEmpty || email.isEmpty) return false;
    try {
      final uri = Uri.parse(logoUrl.trim());
      final logoHost = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      final emailParts = email.trim().split('@');
      if (emailParts.length != 2) return false;
      final emailDomain = emailParts[1].toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      if (logoHost.isEmpty || emailDomain.isEmpty) return false;
      return logoHost == emailDomain || logoHost.endsWith('.$emailDomain') || emailDomain.endsWith('.$logoHost');
    } catch (_) {
      return false;
    }
  }

  String _extractHost(String url) {
    try {
      return Uri.parse(url.trim()).host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return '';
    }
  }

  String _extractEmailDomain(String email) {
    final parts = email.trim().split('@');
    return parts.length == 2 ? parts[1].toLowerCase().replaceFirst(RegExp(r'^www\.'), '') : '';
  }

  Future<void> _handleCreate() async {
    final user = ref.read(currentUserProvider).value;
    if (user == null || !user.isRegistered) {
      AuthGuard.requireHostAuth(context, ref, () => _handleCreate());
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_enableOrgBranding) {
      final orgName = _orgNameController.text.trim();
      final logoUrl = _orgLogoUrlController.text.trim();
      final approverEmail = _orgApproverEmailController.text.trim();

      if (orgName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your Organization / Company Name'), backgroundColor: AppTheme.accentDanger),
        );
        return;
      }
      if (!logoUrl.startsWith('https://')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Official Logo URL must be a valid, secure HTTPS link'), backgroundColor: AppTheme.accentDanger),
        );
        return;
      }
      if (!approverEmail.contains('@') || !approverEmail.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid Corporate Approver Email'), backgroundColor: AppTheme.accentDanger),
        );
        return;
      }
      if (!_isDomainMatching(logoUrl, approverEmail)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Domain Mismatch: Logo URL host must match corporate approver email domain for automated verification.'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }
      if (!_orgVisualConfirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please visually review and check the confirmation box for the live card preview before submitting.'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final activePrizes = _prizes.entries.where((e) => e.value).map((e) => e.key).toList();
      final gameRepo = ref.read(gameRepositoryProvider);

      // Resolve tier UUID from loaded tiers
      String? tierUuid = _selectedTierId;
      final loadedTiers = ref.read(capacityTiersProvider).value;
      if (loadedTiers != null && loadedTiers.isNotEmpty) {
        final match = loadedTiers.firstWhere(
          (t) => t.id == _selectedTierId || t.maxPlayers == _selectedCapacity,
          orElse: () => loadedTiers.first,
        );
        tierUuid = match.id;
      }
      if (tierUuid != null &&
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
              .hasMatch(tierUuid)) {
        tierUuid = null;
      }

      final game = await gameRepo.createGame(
        name: _nameController.text.trim(),
        plannedCapacity: _selectedCapacity,
        plannedCapacityTierId: tierUuid,
        scheduledAt: _scheduledDateTime,
        prizesConfig: activePrizes,
        isPrivate: _isPrivate,
      );

      String? brandApprovalMsg;
      if (_enableOrgBranding) {
        final brandRes = await gameRepo.submitBrandApproval(
          gameId: game.id,
          organizationName: _orgNameController.text.trim(),
          organizationLogoUrl: _orgLogoUrlController.text.trim(),
          approverEmail: _orgApproverEmailController.text.trim(),
        );
        if (brandRes['success'] == true) {
          brandApprovalMsg = 'Approval email dispatched to ${_orgApproverEmailController.text.trim()}. Official branding activates the moment they click approve.';
        }
      }

      if (!mounted) return;
      _showSuccessDialog(game, brandApprovalMessage: brandApprovalMsg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCopyLink(MptGame game) {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct join link copied to clipboard!')),
    );
  }

  Future<void> _handleShare(MptGame game) async {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DabHousie in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap to join or download the app:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  void _showSuccessDialog(MptGame game, {String? brandApprovalMessage}) {
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
                        icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryLight),
                        tooltip: 'Copy Code Only',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: game.inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite code copied to clipboard!')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.link, size: 20, color: AppTheme.primaryLight),
                        tooltip: 'Copy Direct Join Link',
                        onPressed: () => _handleCopyLink(game),
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
            if (brandApprovalMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: AppTheme.accentSuccess, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🏢 Corporate Approval: $brandApprovalMessage',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (game.isPrivate) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentPartyPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentPartyPurple.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: AppTheme.accentPartyPurple, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🔒 Private Party Mode: Single-use passcodes for each seat have been created & emailed to you. You can view, copy, and manage them anytime in your Organizer Lobby.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _handleCopyLink(game),
            icon: const Icon(Icons.link, size: 16, color: AppTheme.primaryLight),
            label: const Text('Copy Link', style: TextStyle(color: AppTheme.primaryLight)),
          ),
          TextButton.icon(
            onPressed: () => _handleShare(game),
            icon: const Icon(Icons.share, size: 16, color: AppTheme.secondaryColor),
            label: const Text('Share Invite', style: TextStyle(color: AppTheme.secondaryColor)),
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
      appBar: const DabHousieAppBar(
        badgeText: 'Host',
        showBackButton: true,
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
                  const SizedBox(height: 16),

                  if (ref.watch(currentUserProvider).value?.isRegistered != true) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined, color: AppTheme.secondaryColor, size: 24),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Host Account Required',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  'Please sign in with Google or Apple to create rooms, schedule parties, and manage player seats.',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => AuthDialog.show(context, isHostContext: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('Sign In'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Game / Event Name',
                      hintText: 'e.g. Diwali Party DabHousie',
                      prefixIcon: const Icon(Icons.celebration),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.casino_outlined, color: AppTheme.secondaryColor),
                        tooltip: 'Shuffle Event Name',
                        onPressed: _randomizeName,
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Please enter game name' : null,
                  ),
                  const SizedBox(height: 16),

                  _buildPrivatePartyToggle(),
                  const SizedBox(height: 16),

                  _buildSchedulePicker(),
                  const SizedBox(height: 16),

                  _buildCorporateBrandingSection(),
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

  Widget _buildCorporateBrandingSection() {
    final logoUrl = _orgLogoUrlController.text.trim();
    final approverEmail = _orgApproverEmailController.text.trim();
    final isMatching = _isDomainMatching(logoUrl, approverEmail);
    final logoHost = _extractHost(logoUrl);
    final emailDomain = _extractEmailDomain(approverEmail);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _enableOrgBranding ? AppTheme.primaryColor.withValues(alpha: 0.1) : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _enableOrgBranding ? AppTheme.primaryLight.withValues(alpha: 0.6) : const Color(0xFF2E334D),
          width: _enableOrgBranding ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _enableOrgBranding ? AppTheme.primaryColor.withValues(alpha: 0.25) : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: AppTheme.secondaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏢 Corporate / Organization Branding (Optional)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Feature your official company logo, brand banner, and verified organization name.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _enableOrgBranding,
                activeThumbColor: AppTheme.secondaryColor,
                onChanged: (val) => setState(() {
                  _enableOrgBranding = val;
                  if (!val) _orgVisualConfirmed = false;
                }),
              ),
            ],
          ),

          if (_enableOrgBranding) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 14),

            // Automated Approval Notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.secondaryColor, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚡ Automated Domain-Verified Approval (DVAA)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'No platform bottleneck! Your corporate approver will receive an automated one-click verification email. Branding activates instantly upon their confirmation.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Form Inputs
            TextFormField(
              controller: _orgNameController,
              decoration: const InputDecoration(
                labelText: 'Organization / Company Name',
                hintText: 'e.g. Acme Corporation, Google, Tata Group',
                prefixIcon: Icon(Icons.corporate_fare_rounded),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _orgLogoUrlController,
              decoration: const InputDecoration(
                labelText: 'Official Logo URL (HTTPS)',
                hintText: 'e.g. https://www.acme.com/assets/logo.png',
                prefixIcon: Icon(Icons.link_rounded),
                helperText: 'Must be hosted on your corporate website domain via HTTPS (Zero file uploads).',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _orgApproverEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Corporate Approver Email',
                hintText: 'e.g. admin@acme.com or events@acme.com',
                prefixIcon: Icon(Icons.mark_email_read_rounded),
                helperText: 'Approval link will be emailed to this address. Email domain must match the logo URL host.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),

            // Domain Matching Status Indicator
            if (logoUrl.isNotEmpty && approverEmail.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isMatching ? AppTheme.accentSuccess.withValues(alpha: 0.15) : AppTheme.accentDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMatching ? AppTheme.accentSuccess.withValues(alpha: 0.5) : AppTheme.accentDanger.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isMatching ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                      color: isMatching ? AppTheme.accentSuccess : AppTheme.accentDanger,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isMatching
                            ? '✅ Domain Match: Logo host ($logoHost) matches approver domain (@$emailDomain)'
                            : '❌ Domain Mismatch: Logo host ($logoHost) does not match approver email domain (@$emailDomain)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isMatching ? AppTheme.accentSuccess : const Color(0xFFFCA5A5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFA0AEC0), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enter both Logo URL and Corporate Email to verify domain match.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Live Card Mock Screen Visual Preview
            _buildLiveCardMock(),

            const SizedBox(height: 14),

            // Organizer Visual Confirmation Checkbox
            Container(
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _orgVisualConfirmed ? AppTheme.primaryLight : const Color(0xFF2E334D),
                  width: _orgVisualConfirmed ? 1.5 : 1,
                ),
              ),
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                value: _orgVisualConfirmed,
                activeColor: AppTheme.primaryColor,
                title: const Text(
                  'I have visually inspected the Live Card Mock above and confirm that the organization name, logo, and domain representation are accurate.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Verification email will only be dispatched to the corporate approver after your confirmation.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ),
                onChanged: (val) => setState(() => _orgVisualConfirmed = val ?? false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveCardMock() {
    final orgName = _orgNameController.text.trim().isEmpty ? 'Your Organization Name' : _orgNameController.text.trim();
    final logoUrl = _orgLogoUrlController.text.trim();
    final eventName = _nameController.text.trim().isEmpty ? 'DabHousie Game Night' : _nameController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.remove_red_eye_rounded, size: 16, color: AppTheme.secondaryColor),
            SizedBox(width: 6),
            Text(
              'Live Event Card Mock Preview (Visual Inspection)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'This is how players and public visitors will see your branded event card:',
          style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.darkCard,
                AppTheme.primaryColor.withValues(alpha: 0.2),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Corporate Header Badge Row
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: logoUrl.isNotEmpty && logoUrl.startsWith('https://')
                        ? Image.network(
                            logoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => Image.asset(AppAssets.monogramDH, fit: BoxFit.contain),
                          )
                        : Image.asset(AppAssets.monogramDH, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                orgName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentSuccess.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.5)),
                              ),
                              child: const Text(
                                'OFFICIAL',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        const Text(
                          'Verified Corporate Event • Hosted on DabHousie',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF334155), height: 1),
              const SizedBox(height: 12),

              // Game Name & Metadata
              Text(
                eventName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildMockChip(
                    icon: Icons.calendar_today_rounded,
                    label: _scheduledDateTime == null ? 'Instant Launch' : _formatDateTime(_scheduledDateTime!),
                    color: AppTheme.secondaryColor,
                  ),
                  _buildMockChip(
                    icon: Icons.people_outline_rounded,
                    label: '$_selectedCapacity Seats',
                    color: Colors.white,
                  ),
                  _buildMockChip(
                    icon: _isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded,
                    label: _isPrivate ? 'Private OTP' : 'Open Room',
                    color: _isPrivate ? AppTheme.accentPartyPurple : AppTheme.primaryLight,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Approval status disclaimer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, color: AppTheme.secondaryColor, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Approval Status: Pending approver one-click verification via ${_orgApproverEmailController.text.trim().isEmpty ? 'corporate email' : _orgApproverEmailController.text.trim()}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildGroupSizeSection() {
    final walletAsync = ref.watch(walletProvider);
    final availableCredits = walletAsync.value?.availableCredits ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Expected Group Size (Capacity)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.secondaryColor, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    'Balance: $availableCredits Credits',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              errorBuilder: (ctx, err, stack) => const Icon(Icons.celebration, color: AppTheme.secondaryColor, size: 30),
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
                      'DabHousie Game Setup',
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

  Widget _buildPrivatePartyToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _isPrivate ? AppTheme.accentPartyPurple.withValues(alpha: 0.15) : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isPrivate ? AppTheme.accentPartyPurple : const Color(0xFF2E334D),
          width: _isPrivate ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isPrivate ? AppTheme.accentPartyPurple.withValues(alpha: 0.25) : AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isPrivate ? Icons.lock_rounded : Icons.public_rounded,
              color: _isPrivate ? AppTheme.accentPartyPurple : const Color(0xFF94A3B8),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Private Party Mode',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (_isPrivate) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPartyPurple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'RESTRICTED • EXTRA CHARGES APPLY',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isPrivate
                      ? 'Single-use OTP passcodes generated for each seat (Zero PII). Additional credit charges apply.'
                      : 'Standard party: Anyone with the 6-character code can enter and join.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isPrivate,
            activeThumbColor: AppTheme.accentPartyPurple,
            onChanged: (val) => setState(() => _isPrivate = val),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacitySelector() {
    final tiersState = ref.watch(capacityTiersProvider);
    final tiers = tiersState.value ?? MptCapacityTier.defaultTiers;
    return _buildTiersList(tiers);
  }

  Widget _buildTiersList(List<MptCapacityTier> tiers) {
    if (tiers.isEmpty) return _buildStaticCapacityOptions();

    // Default to the first tier if unset
    if (_selectedTierId == null && tiers.isNotEmpty) {
      _selectedTierId = tiers.first.id;
      _selectedCapacity = tiers.first.maxPlayers;
    }

    return Column(
      children: [
        ...tiers.map((tier) {
          final isSelected = _selectedTierId == tier.id ||
              (_selectedTierId == null && _selectedCapacity == tier.maxPlayers) ||
              (_selectedCapacity == tier.maxPlayers);
          final breakdownText = _getPrivateCreditBreakdownText(tier.maxPlayers);

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
                        Row(
                          children: [
                            Text(tier.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (_isPrivate) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.lock_outline, size: 13, color: AppTheme.accentPartyPurple),
                            ],
                          ],
                        ),
                        Text(
                          _isPrivate
                              ? '${tier.minPlayers}–${tier.maxPlayers} Seats • $breakdownText (Private OTP)'
                              : (tier.creditsRequired == 0
                                  ? '${tier.minPlayers}–${tier.maxPlayers} Players • Free (0 Credits)*'
                                  : '${tier.minPlayers}–${tier.maxPlayers} Players • ${tier.creditsRequired} Credits'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (!_isPrivate && tier.creditsRequired == 0)
                                ? FontWeight.bold
                                : (_isPrivate ? FontWeight.w600 : FontWeight.normal),
                            color: _isPrivate
                                ? AppTheme.accentPartyPurple
                                : (tier.creditsRequired == 0 ? AppTheme.accentSuccess : AppTheme.secondaryColor),
                          ),
                        ),
                      ],
                    ),
                    Radio<String>(
                      value: tier.id,
                      groupValue: isSelected ? tier.id : null,
                      activeColor: _isPrivate ? AppTheme.accentPartyPurple : AppTheme.primaryColor,
                      onChanged: (val) => setState(() {
                        _selectedTierId = tier.id;
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
  }

  Widget _buildStaticCapacityOptions() {
    final options = [
      {'capacity': 5, 'label': '1–5 Players', 'publicDesc': 'Family Pack • Free (0 Credits)*'},
      {'capacity': 15, 'label': '6–15 Players', 'publicDesc': 'Small Party • 15 Credits'},
      {'capacity': 25, 'label': '16–25 Players', 'publicDesc': 'Medium Group • 25 Credits'},
      {'capacity': 50, 'label': '26–50 Players', 'publicDesc': 'Large Group • 50 Credits'},
      {'capacity': 100, 'label': '51–100 Players', 'publicDesc': 'Club Event • 100 Credits'},
      {'capacity': 250, 'label': '101–250 Players', 'publicDesc': 'Mega Event • 250 Credits'},
    ];

    return Column(
      children: [
        ...options.map((opt) {
          final cap = opt['capacity'] as int;
          final isSelected = _selectedCapacity == cap;
          final breakdownText = _getPrivateCreditBreakdownText(cap);

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
                        Text(
                          _isPrivate
                              ? '$cap Seats • $breakdownText (Private OTP)'
                              : opt['publicDesc'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _isPrivate ? FontWeight.w600 : FontWeight.normal,
                            color: _isPrivate ? AppTheme.accentPartyPurple : const Color(0xFFA0AEC0),
                          ),
                        ),
                      ],
                    ),
                    Radio<int>(
                      value: cap,
                      groupValue: _selectedCapacity,
                      activeColor: _isPrivate ? AppTheme.accentPartyPurple : AppTheme.primaryColor,
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
                    ? 'Play immediately on launch in 🤖 Auto-Pilot or 🎙️ Manual Host mode.'
                    : 'Scheduled for: ${_formatDateTime(_scheduledDateTime!)} (Supports 🤖 Auto-Pilot)',
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

