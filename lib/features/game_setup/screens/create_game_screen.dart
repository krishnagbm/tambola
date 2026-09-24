import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../core/widgets/company_logo.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_game.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/auth_repository.dart';
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
  bool _orgAuthorityConfirmed = false;

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

  late final List<Map<String, String>> _mockWinners;

  void _shuffleMockWinners() {
    final shuffledNicknames = List<String>.from(AuthRepository.defaultNicknames)..shuffle();
    const sampleAvatars = ['🐯', '🐻', '🦅', '🦁', '🦊', '🦄', '🐼', '🧙'];
    _mockWinners = [
      {
        'key': 'FULL_HOUSE',
        'icon': '🏆',
        'prize': 'Full House (Grand Prize)',
        'avatar': sampleAvatars[0],
        'player': shuffledNicknames[0],
        'isGrand': 'true',
      },
      {
        'key': 'TOP_LINE',
        'icon': '🥇',
        'prize': 'Top Line',
        'avatar': sampleAvatars[1],
        'player': shuffledNicknames[1],
        'isGrand': 'false',
      },
      {
        'key': 'MIDDLE_LINE',
        'icon': '🥈',
        'prize': 'Middle Line',
        'avatar': sampleAvatars[2],
        'player': shuffledNicknames[2],
        'isGrand': 'false',
      },
      {
        'key': 'BOTTOM_LINE',
        'icon': '🥉',
        'prize': 'Bottom Line',
        'avatar': sampleAvatars[3],
        'player': shuffledNicknames[3],
        'isGrand': 'false',
      },
      {
        'key': 'EARLY_FIVE',
        'icon': '⚡',
        'prize': 'Early 5 (Jaldi 5)',
        'avatar': sampleAvatars[4],
        'player': shuffledNicknames[4],
        'isGrand': 'false',
      },
      {
        'key': 'FOUR_CORNERS',
        'icon': '🎯',
        'prize': 'Four Corners',
        'avatar': sampleAvatars[5],
        'player': shuffledNicknames[5],
        'isGrand': 'false',
      },
      {
        'key': 'SECOND_FULL_HOUSE',
        'icon': '🏆',
        'prize': '2nd Full House',
        'avatar': sampleAvatars[6],
        'player': shuffledNicknames[6],
        'isGrand': 'false',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    final initialName = (List<String>.from(_suggestedNames)..shuffle()).first;
    _nameController = TextEditingController(text: initialName)..addListener(() => setState(() {}));
    _orgNameController = TextEditingController()..addListener(() => setState(() {}));
    _orgLogoUrlController = TextEditingController()..addListener(() => setState(() {}));
    _orgApproverEmailController = TextEditingController()..addListener(() => setState(() {}));
    _shuffleMockWinners();
  }

  void _randomizeName() {
    final nextName = (List<String>.from(_suggestedNames)..shuffle()).first;
    final shuffledNicknames = List<String>.from(AuthRepository.defaultNicknames)..shuffle();
    setState(() {
      _nameController.text = nextName;
      for (var i = 0; i < _mockWinners.length && i < shuffledNicknames.length; i++) {
        _mockWinners[i]['player'] = shuffledNicknames[i];
      }
    });
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
      final logoHost = _extractHost(logoUrl);
      final emailDomain = _extractEmailDomain(email);
      if (logoHost.isEmpty || emailDomain.isEmpty) return false;
      return logoHost == emailDomain || logoHost.endsWith('.$emailDomain') || emailDomain.endsWith('.$logoHost');
    } catch (_) {
      return false;
    }
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      if (host == 'img.logo.dev' || host == 'logo.dev') {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          return segments.first.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
        }
      }
      return host;
    } catch (_) {
      return '';
    }
  }

  static const _personalEmailDomains = {
    'gmail.com',
    'yahoo.com',
    'ymail.com',
    'hotmail.com',
    'outlook.com',
    'live.com',
    'msn.com',
    'aol.com',
    'icloud.com',
    'me.com',
    'mac.com',
    'proton.me',
    'protonmail.com',
    'zoho.com',
    'mail.com',
    'gmx.com',
    'yandex.com',
    'rediffmail.com',
  };

  bool _isPersonalDomain(String domain) {
    return _personalEmailDomains.contains(domain.toLowerCase().trim());
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
      final approverEmail = _orgApproverEmailController.text.trim().toLowerCase();
      final hostEmail = (user.email ?? '').trim().toLowerCase();
      final hostDomain = _extractEmailDomain(hostEmail);
      final approverDomain = _extractEmailDomain(approverEmail);

      if (hostEmail.isEmpty || _isPersonalDomain(hostDomain)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Security Gate: Corporate branding requires hosting from an official company email address, not a personal email provider.'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }

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
      if (_isPersonalDomain(approverDomain)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Security Gate: Corporate approver email cannot be a personal email address (e.g. Gmail, Yahoo).'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }
      final isHostApproverMatch = hostDomain == approverDomain ||
          hostDomain.endsWith('.$approverDomain') ||
          approverDomain.endsWith('.$hostDomain');
      if (!isHostApproverMatch) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Domain Mismatch: Your host email domain (@$hostDomain) must match the approver email domain (@$approverDomain).'),
            backgroundColor: AppTheme.accentDanger,
          ),
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
            content: Text('Please inspect the Live Card Mock and check the Visual Confirmation box before proceeding.'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
        return;
      }
      if (!_orgAuthorityConfirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please confirm organizational representation & DVAA™ authorization by checking the consent box.'),
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
      bool isBrandSelfApproved = false;
      if (_enableOrgBranding) {
        final approverEmail = _orgApproverEmailController.text.trim();
        final brandRes = await gameRepo.submitBrandApproval(
          gameId: game.id,
          organizationName: _orgNameController.text.trim(),
          organizationLogoUrl: _orgLogoUrlController.text.trim(),
          approverEmail: approverEmail,
          gameName: game.name,
          capacity: game.fundedCapacity,
          inviteCode: game.inviteCode,
        );
        isBrandSelfApproved = brandRes['is_self_approved'] == true;
        if (isBrandSelfApproved) {
          brandApprovalMsg = 'DVAA™ Verified! Official branding has been automatically approved and activated for your event. An official acknowledgement email and audit copy have been dispatched to $approverEmail and contact@dabhousie.com.';
        } else if (brandRes['success'] == true) {
          brandApprovalMsg = 'DVAA™ authorization request successfully sent to $approverEmail with an audit copy to contact@dabhousie.com. Official branding will automatically appear on the event live card and Hall of Fame the moment they click approve.';
        } else {
          brandApprovalMsg = 'Approval record saved. (Note: ${brandRes['message'] ?? 'Check your email inbox or spam folder'}).';
        }
      }

      if (!mounted) return;
      _showSuccessDialog(game, brandApprovalMessage: brandApprovalMsg, isSelfApproved: isBrandSelfApproved);
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

  void _showSuccessDialog(MptGame game, {String? brandApprovalMessage, bool isSelfApproved = false}) {
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
                  color: isSelfApproved
                      ? AppTheme.accentSuccess.withValues(alpha: 0.15)
                      : AppTheme.secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelfApproved
                        ? AppTheme.accentSuccess.withValues(alpha: 0.5)
                        : AppTheme.secondaryColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isSelfApproved ? Icons.verified_user_rounded : Icons.mark_email_read_rounded,
                      color: isSelfApproved ? AppTheme.accentSuccess : AppTheme.secondaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isSelfApproved
                            ? '🏢 Corporate Branding: $brandApprovalMessage'
                            : '🏢 Corporate Approval: $brandApprovalMessage',
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
    final hostUser = ref.watch(currentUserProvider).value;
    final hostEmail = (hostUser?.email ?? '').trim().toLowerCase();
    final hostDomain = _extractEmailDomain(hostEmail);
    final isHostPersonal = hostEmail.isEmpty || _isPersonalDomain(hostDomain);

    final logoUrl = _orgLogoUrlController.text.trim();
    final approverEmail = _orgApproverEmailController.text.trim().toLowerCase();
    final isMatching = _isDomainMatching(logoUrl, approverEmail);
    final logoHost = _extractHost(logoUrl);
    final emailDomain = _extractEmailDomain(approverEmail);
    final isHostApproverMatch = hostDomain.isNotEmpty &&
        (hostDomain == emailDomain || hostDomain.endsWith('.$emailDomain') || emailDomain.endsWith('.$hostDomain'));
    final isSelfApproval = !isHostPersonal && hostEmail.isNotEmpty && hostEmail == approverEmail;

    final rawOrgName = _orgNameController.text.trim();
    final suggestedDomain = emailDomain.isNotEmpty
        ? emailDomain
        : (hostDomain.isNotEmpty && !isHostPersonal
            ? hostDomain
            : (rawOrgName.contains('.')
                ? CompanyLogo.cleanDomain(rawOrgName)
                : (rawOrgName.isNotEmpty
                    ? '${rawOrgName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.com'
                    : '')));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (!isHostPersonal && _enableOrgBranding)
            ? AppTheme.primaryColor.withValues(alpha: 0.1)
            : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (!isHostPersonal && _enableOrgBranding)
              ? AppTheme.primaryLight.withValues(alpha: 0.6)
              : const Color(0xFF2E334D),
          width: (!isHostPersonal && _enableOrgBranding) ? 1.5 : 1,
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
                  color: (!isHostPersonal && _enableOrgBranding)
                      ? AppTheme.primaryColor.withValues(alpha: 0.25)
                      : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.business_rounded,
                  color: isHostPersonal ? const Color(0xFF64748B) : AppTheme.secondaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '🏢 Corporate / Org Branding',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (isHostPersonal) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 11, color: Color(0xFF94A3B8)),
                                SizedBox(width: 3),
                                Text(
                                  'Corporate Only',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHostPersonal
                          ? (hostEmail.isNotEmpty
                              ? 'Disabled for personal accounts ($hostEmail). Corporate domain login required.'
                              : 'Feature official logo & branding. Corporate domain login required.')
                          : 'Feature your official company logo, brand banner, and verified organization name.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isHostPersonal ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
              if (isHostPersonal) ...[
                TextButton(
                  onPressed: () => AuthDialog.show(context, isHostContext: true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Switch Account', style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryColor)),
                ),
              ] else ...[
                Switch.adaptive(
                  value: _enableOrgBranding,
                  activeThumbColor: AppTheme.secondaryColor,
                  onChanged: (val) => setState(() {
                    _enableOrgBranding = val;
                    if (!val) {
                      _orgVisualConfirmed = false;
                      _orgAuthorityConfirmed = false;
                    }
                  }),
                ),
              ],
            ],
          ),

          if (!isHostPersonal && _enableOrgBranding) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 14),

            if (isSelfApproval) ...[
              // Instant Domain-Owner DVAA™ Authorization
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_rounded, color: AppTheme.accentSuccess, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔒 DVAA™ (Domain-Verified Automated Approval)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Because you are verified under @$hostDomain via corporate email authentication, your event qualifies for instant brand activation under DVAA™. Official branding will be automatically activated upon creation, with an audit confirmation emailed to you and contact@dabhousie.com.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              // Automated Approval Notice for 3rd-party approver in same domain
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.mark_email_read_rounded, color: AppTheme.secondaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔒 Private Corporate Approval Required',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            approverEmail.isNotEmpty
                                ? 'A private verification link will be sent directly to $approverEmail. For security, authorization links are never displayed on the host screen.'
                                : 'An automated verification link will be sent to the corporate approver. Approval links are private and never displayed on the host screen.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

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
                helperText: 'Must be hosted on your corporate website domain via HTTPS (or auto-fetch via Logo.dev).',
                helperMaxLines: 2,
              ),
            ),
            if (suggestedDomain.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final logoUrl = CompanyLogo.buildLogoUrl(domain: suggestedDomain, size: 256);
                    setState(() {
                      _orgLogoUrlController.text = logoUrl;
                    });
                  },
                  icon: const Icon(Icons.auto_awesome, size: 14, color: AppTheme.secondaryColor),
                  label: Text(
                    'Auto-fetch official logo for $suggestedDomain (via Logo.dev)',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    backgroundColor: AppTheme.secondaryColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '💡 Commercial projects on the free Community plan require a visible Logo.dev link. Personal projects do not require attribution.',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), height: 1.3),
                ),
              ),
            ],
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
            if (!isHostPersonal && hostEmail.isNotEmpty && approverEmail != hostEmail) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _orgApproverEmailController.text = hostEmail),
                  icon: const Icon(Icons.person_outline_rounded, size: 14, color: AppTheme.secondaryColor),
                  label: Text(
                    'I am the approver (use $hostEmail)',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    backgroundColor: AppTheme.secondaryColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Domain Matching Status Indicator
            if (approverEmail.isNotEmpty && _isPersonalDomain(emailDomain)) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '❌ Invalid Domain: Corporate approver email cannot be a personal email (@$emailDomain). Must be your organization\'s official email domain.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!isHostPersonal && approverEmail.isNotEmpty && !isHostApproverMatch) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '❌ Host Domain Mismatch: Approver email domain (@$emailDomain) must match your host domain (@$hostDomain). You may only request branding for your own organization.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (logoUrl.isNotEmpty && approverEmail.isNotEmpty) ...[
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
                            ? (isSelfApproval
                                ? '✅ Domain Match: Verified for @$emailDomain (Instant Auto-Approval)'
                                : '✅ Domain Match: Logo host ($logoHost) matches approver domain (@$emailDomain)')
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

            // Visual Verification & Live Card Mock Preview (Side-by-side on desktop/tablet to save vertical space)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final checkCard = _buildVisualConfirmationCard(
                  isMatching: isMatching,
                  isWide: isWide,
                  isSelfApproval: isSelfApproval,
                );
                final mockCard = _buildLiveCardMock();

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: checkCard,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: mockCard,
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      mockCard,
                      const SizedBox(height: 14),
                      checkCard,
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 16),

            // Footnote: Logo.dev Attribution Terms & Guidelines
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.secondaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Logo Attribution Policy',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), height: 1.45),
                            children: [
                              const TextSpan(
                                text: 'Commercial projects utilizing logos on the free Logo.dev Community plan require a visible attribution link (automatically embedded in public Live Event Cards & Hall of Fame results). Personal projects and private parties do not require attribution. ',
                              ),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: InkWell(
                                  onTap: () async {
                                    final uri = Uri.parse('https://logo.dev');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  child: const Text(
                                    'Learn more at Logo.dev',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.secondaryColor,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisualConfirmationCard({
    required bool isMatching,
    required bool isWide,
    bool isSelfApproval = false,
  }) {
    final user = ref.watch(currentUserProvider).value;
    final hostEmail = (user?.email ?? '').trim();
    final approverEmail = _orgApproverEmailController.text.trim();
    final orgName = _orgNameController.text.trim().isEmpty ? 'Your Organization' : _orgNameController.text.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _orgVisualConfirmed ? AppTheme.primaryLight : const Color(0xFF2E334D),
          width: _orgVisualConfirmed ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fact_check_rounded, color: AppTheme.secondaryColor, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Visual Verification & Consent',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isSelfApproval
                ? 'Review the Hall of Fame preview${isWide ? ' on the right' : ''} to confirm that your organization name, logo, and event presentation appear as intended. Branding activates immediately upon creation.'
                : 'Before dispatching the automated corporate verification email, inspect the Hall of Fame preview${isWide ? ' on the right' : ''} to confirm that the organization name, logo, and event presentation appear as intended.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.corporate_fare_rounded, size: 14, color: AppTheme.secondaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Organization: $orgName',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.mark_email_read_rounded, size: 14, color: AppTheme.secondaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        approverEmail.isEmpty ? 'Approver: Corporate email pending' : 'Approver: $approverEmail',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isSelfApproval
                          ? Icons.verified_user_rounded
                          : (isMatching ? Icons.check_circle_rounded : Icons.info_outline_rounded),
                      size: 14,
                      color: (isSelfApproval || isMatching) ? AppTheme.accentSuccess : const Color(0xFFA0AEC0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isSelfApproval
                            ? 'Domain Match: Verified (Instant DVAA™ Approval)'
                            : (isMatching ? 'Domain Match: Verified (DVAA™ Protocol)' : 'Domain Match: Required for DVAA™ dispatch'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: (isSelfApproval || isMatching) ? AppTheme.accentSuccess : const Color(0xFFA0AEC0),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Checkbox 1: Visual Inspection & Mock Confirmation
          InkWell(
            onTap: () => setState(() => _orgVisualConfirmed = !_orgVisualConfirmed),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orgVisualConfirmed
                    ? AppTheme.primaryLight.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _orgVisualConfirmed ? AppTheme.primaryLight : const Color(0xFF334155),
                  width: _orgVisualConfirmed ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _orgVisualConfirmed,
                    activeColor: AppTheme.primaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) => setState(() => _orgVisualConfirmed = val ?? false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'I have visually inspected the Live Card Mock and confirm that the organization name, logo, and domain representation are accurate.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSelfApproval
                              ? 'DVAA™ Instant Verification: Official branding will be automatically activated upon game creation.'
                              : 'DVAA™ Verification email will only be dispatched to the corporate approver after your confirmation.',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Checkbox 2: Authority Representation & DVAA™ Audit Consent
          InkWell(
            onTap: () => setState(() => _orgAuthorityConfirmed = !_orgAuthorityConfirmed),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orgAuthorityConfirmed
                    ? AppTheme.secondaryColor.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _orgAuthorityConfirmed ? AppTheme.secondaryColor : const Color(0xFF334155),
                  width: _orgAuthorityConfirmed ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _orgAuthorityConfirmed,
                    activeColor: AppTheme.secondaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) => setState(() => _orgAuthorityConfirmed = val ?? false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSelfApproval
                              ? 'I confirm that I am an authorized corporate representative of ${orgName.isEmpty ? "this organization" : orgName} and officially authorize displaying our corporate branding for this event.'
                              : 'I confirm that I am requesting branding on behalf of ${orgName.isEmpty ? "this organization" : orgName}, and that ${approverEmail.isEmpty ? "the corporate approver" : approverEmail} is authorized to approve this request.',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSelfApproval
                              ? 'DVAA™ Compliance: An immutable confirmation & audit record will be emailed to $hostEmail and contact@dabhousie.com.'
                              : 'DVAA™ Compliance: An authorization request email will be dispatched to ${approverEmail.isEmpty ? "the corporate approver" : approverEmail} with an audit copy to contact@dabhousie.com.',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
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

  Widget _buildLiveCardMock() {
    final orgName = _orgNameController.text.trim().isEmpty ? 'Your Organization Name' : _orgNameController.text.trim();
    final logoUrl = _orgLogoUrlController.text.trim();
    final eventName = _nameController.text.trim().isEmpty ? 'DabHousie Fiesta 🎊' : _nameController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.remove_red_eye_rounded, size: 16, color: AppTheme.secondaryColor),
            const SizedBox(width: 6),
            const Text(
              'Live Event Card Mock Preview',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Hall of Fame Style', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // The Hall of Fame Card
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E293B)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rainbow top gradient bar
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFFFFC107), Color(0xFF10B981)],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: Game Title & Code Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            eventName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFBE0B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x59FFBE0B)),
                          ),
                          child: const Text(
                            'CA8E81',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Corporate Org Badge (if enabled)
                    if (_enableOrgBranding) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildMockLogo(logoUrl),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Hosted by $orgName',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.accentSuccess.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'OFFICIAL',
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Meta Row
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildHallOfFameMetaItem(
                          icon: '👥',
                          value: '$_selectedCapacity Players',
                        ),
                        _buildHallOfFameMetaItem(
                          icon: '🎯',
                          value: '68/90 Calls',
                        ),
                        _buildHallOfFameMetaItem(
                          icon: '⏱️',
                          value: '10m 55s',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildHallOfFameMetaItem(
                      icon: '📅',
                      value: _formatMockDate(_scheduledDateTime),
                    ),

                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFF1E293B), height: 1),
                    const SizedBox(height: 12),

                    // Verified Prize Winners Section Title
                    const Text(
                      'VERIFIED PRIZE WINNERS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Winner rows mimicking Hall of Fame card
                    ..._buildMockWinnersList(),

                    if (_orgApproverEmailController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded, color: AppTheme.secondaryColor, size: 12),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Pending verification via ${_orgApproverEmailController.text.trim()}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_enableOrgBranding && !_isPrivate && (logoUrl.contains('logo.dev') || (logoUrl.isEmpty && _extractEmailDomain(_orgApproverEmailController.text).isNotEmpty))) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () async {
                            final uri = Uri.parse('https://logo.dev');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Logos provided by ',
                                style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                              ),
                              Text(
                                'Logo.dev',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: Color(0xFF94A3B8),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMockWinnersList() {
    final activePrizes = _mockWinners.where((w) {
      final key = w['key']!;
      return _prizes[key] ?? false;
    }).toList();

    final listToDisplay = activePrizes.isEmpty ? _mockWinners.take(4).toList() : activePrizes;

    return listToDisplay.map((winner) {
      final isGrand = winner['isGrand'] == 'true';
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isGrand ? const Color(0x1FFFBE0B) : const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isGrand ? const Color(0x4DFFBE0B) : const Color(0xFF1E293B),
            width: isGrand ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(winner['icon']!, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(
                  winner['prize']!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isGrand ? const Color(0xFFFCD34D) : const Color(0xFFF8FAFC),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(winner['avatar']!, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(
                  winner['player']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildHallOfFameMetaItem({required String icon, required String value}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  String _formatMockDate(DateTime? dt) {
    final d = dt ?? DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _buildMockLogo(String logoUrl) {
    final cleanLogoDomain = CompanyLogo.cleanDomain(logoUrl);
    final fallbackMonogram = Image.asset(AppAssets.monogramDH, fit: BoxFit.contain);

    // 1. Direct Logo.dev URL (from auto-fetch or manual paste):
    if (logoUrl.contains('img.logo.dev') || logoUrl.contains('logo.dev')) {
      return AutoTrimmedNetworkLogo(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        fallback: fallbackMonogram,
      );
    }

    // 2. User typed a plain domain in the Logo URL field (e.g. 'stripe.com' or 'google.com'):
    if (cleanLogoDomain.contains('.') && !logoUrl.startsWith('http')) {
      return CompanyLogo(
        domain: cleanLogoDomain,
        size: 28,
        isCommercialUse: false,
        fallbackWidget: fallbackMonogram,
      );
    }

    // 3. User entered an HTTPS image URL (non-Logo.dev):
    if (logoUrl.startsWith('https://')) {
      final webProxyUrl = 'https://images.weserv.nl/?url=${Uri.encodeComponent(logoUrl)}';
      final primaryUrl = kIsWeb ? webProxyUrl : logoUrl;
      final fallbackUrl = kIsWeb ? logoUrl : null;

      return AutoTrimmedNetworkLogo(
        imageUrl: primaryUrl,
        fallbackUrl: fallbackUrl,
        fit: BoxFit.contain,
        fallback: fallbackMonogram,
      );
    }

    // 4. Logo URL is empty, check Corporate Approver Email domain:
    final emailDomain = _extractEmailDomain(_orgApproverEmailController.text);
    if (emailDomain.isNotEmpty) {
      return CompanyLogo(
        domain: emailDomain,
        size: 28,
        isCommercialUse: false,
        fallbackWidget: fallbackMonogram,
      );
    }

    // 5. Logo URL is empty, check if Organization Name is or contains a domain:
    final rawOrg = _orgNameController.text.trim();
    final cleanOrgDomain = CompanyLogo.cleanDomain(rawOrg);
    if (cleanOrgDomain.contains('.') && cleanOrgDomain.length > 3) {
      return CompanyLogo(
        domain: cleanOrgDomain,
        size: 28,
        isCommercialUse: false,
        fallbackWidget: fallbackMonogram,
      );
    }

    return fallbackMonogram;
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

