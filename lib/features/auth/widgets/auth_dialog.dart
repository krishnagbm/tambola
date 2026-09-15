import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  String? _loadingProvider;
  bool _showEmailOption = false;
  String? _statusMessage;
  bool _isSuccess = false;

  /// Control flag to reveal Apple button.
  static const bool _showApple = true;

  /// Control flag to reveal Microsoft button.
  static const bool _showMicrosoft = false;

  /// Control flag for email magic link. Disabled to avoid unbranded/junk email issues.
  static const bool _enableEmailMagicLink = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleOAuthSignIn(String provider, Future<void> Function() signInAction) async {
    setState(() {
      _isLoading = true;
      _loadingProvider = provider;
      _statusMessage = null;
    });

    try {
      await signInAction();
      if (mounted) {
        Navigator.pop(context);
        widget.onAuthenticated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
          _statusMessage = '$provider sign-in failed: $e';
          _isSuccess = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authRepo = ref.read(authRepositoryProvider);
    await _handleOAuthSignIn('Google', () => authRepo.signInWithGoogle());
  }

  Future<void> _handleMicrosoftSignIn() async {
    final authRepo = ref.read(authRepositoryProvider);
    await _handleOAuthSignIn('Microsoft', () => authRepo.signInWithMicrosoft());
  }

  Future<void> _handleAppleSignIn() async {
    final authRepo = ref.read(authRepositoryProvider);
    await _handleOAuthSignIn('Apple', () => authRepo.signInWithApple());
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
      _loadingProvider = 'email';
      _statusMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithEmail(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
          _statusMessage = '✨ Magic link sent to $email! Please check your inbox.';
          _isSuccess = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        String msg = e.message;
        if (msg.toLowerCase().contains('email logins are disabled') ||
            e.statusCode == '422') {
          msg = 'Email sign-in is disabled in Supabase. Please use Google Sign-In.';
        }
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
          _statusMessage = msg;
          _isSuccess = false;
        });
      }
    } catch (e) {
      if (mounted) {
        var msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.toLowerCase().contains('email logins are disabled')) {
          msg = 'Email sign-in is disabled in Supabase. Please use Google Sign-In.';
        }
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
          _statusMessage = msg;
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

              // OAuth Buttons Section (PocketBull style)
              _buildOAuthButton(
                icon: const CustomPaint(
                  size: Size(22, 22),
                  painter: GoogleLogoPainter(),
                ),
                title: 'Google',
                subtitle: 'Continue with your Google Account',
                isLoading: _isLoading && _loadingProvider == 'Google',
                onTap: _isLoading ? null : _handleGoogleSignIn,
              ),
              if (_showApple) ...[
                const SizedBox(height: 10),
                _buildOAuthButton(
                  icon: const CustomPaint(
                    size: Size(22, 22),
                    painter: AppleLogoPainter(),
                  ),
                  title: 'Apple',
                  subtitle: 'Continue with your Apple ID',
                  isLoading: _isLoading && _loadingProvider == 'Apple',
                  onTap: _isLoading ? null : _handleAppleSignIn,
                ),
              ],
              if (_showMicrosoft) ...[
                const SizedBox(height: 10),
                _buildOAuthButton(
                  icon: const CustomPaint(
                    size: Size(22, 22),
                    painter: MicrosoftLogoPainter(),
                  ),
                  title: 'Microsoft',
                  subtitle: 'Continue with Microsoft Account',
                  isLoading: _isLoading && _loadingProvider == 'Microsoft',
                  onTap: _isLoading ? null : _handleMicrosoftSignIn,
                ),
              ],
              if (_enableEmailMagicLink) ...[
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
              ],
              const SizedBox(height: 18),

              // Legal Note (Positioned above guest card)
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'By signing in, you agree to our ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    InkWell(
                      onTap: () => _launchLegalUrl('${AppConfig.appBaseUrl}/terms-conditions.html'),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        child: Text(
                          'Terms',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF60A5FA),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      ' & ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    InkWell(
                      onTap: () => _launchLegalUrl('${AppConfig.appBaseUrl}/privacy-policy.html'),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF60A5FA),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Interactive Guest Reassurance & Direct Join Game Card
              Material(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    context.push('/join');
                  },
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: const Color(0xFF1E293B),
                  splashColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E334D)),
                    ),
                    child: Row(
                      children: [
                        const Text('🎉', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Playing as a guest?',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Join a game with an invite code without signing in.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFA0AEC0),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Join Game',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: AppTheme.secondaryColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOAuthButton({
    required Widget icon,
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFF1E293B),
        splashColor: AppTheme.primaryColor.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E334D), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFF64748B),
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
}

/// Official 4-color Google vector logo painter
class GoogleLogoPainter extends CustomPainter {
  const GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    // Blue (#4285F4)
    final bluePaint = Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.fill;
    final bluePath = Path()
      ..moveTo(22.56, 12.25)
      ..cubicTo(22.56, 11.47, 22.49, 10.72, 22.36, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.26)
      ..lineTo(17.92, 14.26)
      ..cubicTo(17.66, 15.63, 16.88, 16.79, 15.71, 17.57)
      ..lineTo(15.71, 20.34)
      ..lineTo(19.28, 20.34)
      ..cubicTo(21.36, 18.42, 22.56, 15.6, 22.56, 12.25)
      ..close();
    canvas.drawPath(bluePath, bluePaint);

    // Green (#34A853)
    final greenPaint = Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.fill;
    final greenPath = Path()
      ..moveTo(12.0, 23.0)
      ..cubicTo(14.97, 23.0, 17.46, 22.02, 19.28, 20.34)
      ..lineTo(15.71, 17.57)
      ..cubicTo(14.73, 18.23, 13.48, 18.63, 12.0, 18.63)
      ..cubicTo(9.14, 18.63, 6.71, 16.7, 5.84, 14.1)
      ..lineTo(2.18, 14.1)
      ..lineTo(2.18, 16.94)
      ..cubicTo(3.99, 20.53, 7.7, 23.0, 12.0, 23.0)
      ..close();
    canvas.drawPath(greenPath, greenPaint);

    // Yellow (#FBBC05)
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.fill;
    final yellowPath = Path()
      ..moveTo(5.84, 14.09)
      ..cubicTo(5.62, 13.43, 5.49, 12.73, 5.49, 12.0)
      ..cubicTo(5.49, 11.27, 5.62, 10.57, 5.84, 9.91)
      ..lineTo(5.84, 7.07)
      ..lineTo(2.18, 7.07)
      ..cubicTo(1.43, 8.55, 1.0, 10.22, 1.0, 12.0)
      ..cubicTo(1.0, 13.78, 1.43, 15.45, 2.18, 16.93)
      ..lineTo(5.84, 14.09)
      ..close();
    canvas.drawPath(yellowPath, yellowPaint);

    // Red (#EA4335)
    final redPaint = Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.fill;
    final redPath = Path()
      ..moveTo(12.0, 5.38)
      ..cubicTo(13.62, 5.38, 15.06, 5.94, 16.21, 7.02)
      ..lineTo(19.36, 3.87)
      ..cubicTo(17.45, 2.09, 14.97, 1.0, 12.0, 1.0)
      ..cubicTo(7.7, 1.0, 3.99, 3.47, 2.18, 7.07)
      ..lineTo(5.84, 9.91)
      ..cubicTo(6.71, 7.31, 9.14, 5.38, 12.0, 5.38)
      ..close();
    canvas.drawPath(redPath, redPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// Official Microsoft 4-square vector logo painter
class MicrosoftLogoPainter extends CustomPainter {
  const MicrosoftLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    canvas.drawRect(const Rect.fromLTWH(2, 2, 9.4, 9.4), Paint()..color = const Color(0xFFF25022));
    canvas.drawRect(const Rect.fromLTWH(12.6, 2, 9.4, 9.4), Paint()..color = const Color(0xFF7FBA00));
    canvas.drawRect(const Rect.fromLTWH(2, 12.6, 9.4, 9.4), Paint()..color = const Color(0xFF00A4EF));
    canvas.drawRect(const Rect.fromLTWH(12.6, 12.6, 9.4, 9.4), Paint()..color = const Color(0xFFFFB900));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// Official Apple monochrome vector logo painter
class AppleLogoPainter extends CustomPainter {
  const AppleLogoPainter({this.color = Colors.white});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);
    final paint = Paint()..color = color..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(18.71, 19.5)
      ..cubicTo(17.88, 20.74, 17.0, 21.95, 15.66, 21.97)
      ..cubicTo(14.32, 22.0, 13.89, 21.18, 12.37, 21.18)
      ..cubicTo(10.84, 21.18, 10.37, 21.95, 9.1, 22.0)
      ..cubicTo(7.79, 22.05, 6.8, 20.68, 5.96, 19.47)
      ..cubicTo(4.25, 17.0, 2.94, 12.45, 4.7, 9.39)
      ..cubicTo(5.57, 7.87, 7.13, 6.91, 8.82, 6.88)
      ..cubicTo(10.1, 6.86, 11.32, 7.75, 12.11, 7.75)
      ..cubicTo(12.89, 7.75, 14.37, 6.68, 15.91, 6.84)
      ..cubicTo(16.56, 6.87, 18.38, 7.1, 19.55, 8.82)
      ..cubicTo(19.46, 8.88, 17.38, 10.1, 17.4, 12.63)
      ..cubicTo(17.43, 15.65, 20.05, 16.66, 20.08, 16.67)
      ..cubicTo(20.05, 16.74, 19.66, 18.11, 18.71, 19.5)
      ..close()
      ..moveTo(13.0, 3.5)
      ..cubicTo(13.73, 2.67, 14.94, 2.04, 15.94, 2.0)
      ..cubicTo(16.07, 3.17, 15.6, 4.35, 14.9, 5.19)
      ..cubicTo(14.21, 6.04, 13.07, 6.7, 11.95, 6.61)
      ..cubicTo(11.8, 5.46, 12.36, 4.26, 13.0, 3.5)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
