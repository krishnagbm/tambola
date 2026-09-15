import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class AuthDialog extends ConsumerStatefulWidget {
  final bool isHostContext;
  final VoidCallback? onAuthenticated;

  const AuthDialog({
    super.key,
    this.isHostContext = false,
    this.onAuthenticated,
  });

  static Future<void> show(
    BuildContext context, {
    bool isHostContext = false,
    VoidCallback? onAuthenticated,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AuthDialog(
        isHostContext: isHostContext,
        onAuthenticated: onAuthenticated,
      ),
    );
  }

  @override
  ConsumerState<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<AuthDialog> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _showEmailOption = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithGoogle();
      if (mounted) {
        Navigator.pop(context);
        widget.onAuthenticated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Google Sign-In failed: $e';
          _isSuccess = false;
        });
      }
    }
  }

  Future<void> _handleEmailSignIn() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _statusMessage = 'Please enter a valid email address';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithEmail(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✨ Magic link sent to $email! Please check your inbox.';
          _isSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to send login link: $e';
          _isSuccess = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF2E334D), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with DabHousie Logo & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset(
                    AppAssets.horizontalLogo,
                    height: 38,
                    fit: BoxFit.contain,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFA0AEC0)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                widget.isHostContext
                    ? 'Sign in to Host & Schedule'
                    : 'Sign In to DabHousie',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                widget.isHostContext
                    ? 'Hosting live DabHousie parties, scheduling games, and managing room seats requires an authenticated account.'
                    : 'Sign in to protect your wallet credits, save your hosted games, and keep your profile synced across devices.',
                style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1), height: 1.4),
              ),
              const SizedBox(height: 24),

              // Status / Error Banner
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? AppTheme.accentSuccess.withValues(alpha: 0.15)
                        : AppTheme.accentDanger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSuccess ? AppTheme.accentSuccess : AppTheme.accentDanger,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSuccess ? Icons.mark_email_read_outlined : Icons.error_outline,
                        color: _isSuccess ? AppTheme.accentSuccess : AppTheme.accentDanger,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _isSuccess ? AppTheme.accentSuccess : AppTheme.accentDanger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Google Sign-In Button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1F2937),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1F2937)),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildGoogleGLogo(),
                          const SizedBox(width: 12),
                          const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFF2E334D))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFF2E334D))),
                ],
              ),
              const SizedBox(height: 14),

              // Email Magic Link Toggle / Input
              if (!_showEmailOption)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showEmailOption = true),
                  icon: const Icon(Icons.email_outlined, size: 18, color: AppTheme.secondaryColor),
                  label: const Text('Sign in with Email Link', style: TextStyle(color: AppTheme.secondaryColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF2E334D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'you@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send_rounded, color: AppTheme.primaryColor),
                      onPressed: _isLoading ? null : _handleEmailSignIn,
                    ),
                  ),
                  onSubmitted: (_) => _handleEmailSignIn(),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleEmailSignIn,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Magic Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Guest Reassurance Callout
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: const Row(
                  children: [
                    Text('🎉', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Playing as a guest? You can join and play games with invite links without signing in.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Legal Note
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'By signing in, you agree to our ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                    InkWell(
                      onTap: () => _launchLegalUrl('${AppConfig.appBaseUrl}/terms-conditions.html'),
                      child: const Text(
                        'Terms',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Text(
                      ' & ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                    InkWell(
                      onTap: () => _launchLegalUrl('${AppConfig.appBaseUrl}/privacy-policy.html'),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildGoogleGLogo() {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            fontFamily: 'Roboto',
            color: const Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
