import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/app_providers.dart';

class VerifyRewardScreen extends ConsumerStatefulWidget {
  const VerifyRewardScreen({super.key});

  @override
  ConsumerState<VerifyRewardScreen> createState() => _VerifyRewardScreenState();
}

class _VerifyRewardScreenState extends ConsumerState<VerifyRewardScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  Map<String, dynamic>? _verificationResult;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _verificationResult = null;
    });

    try {
      final res = await ref.read(rewardsRepositoryProvider).verifyReward(code);
      setState(() => _verificationResult = res);
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Prize Reward'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the voucher code shown on the winner’s phone:',
              style: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'e.g. MPT-REW-7K9Q-X4M2',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isVerifying ? null : _handleVerify,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                  child: _isVerifying
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verify'),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentDanger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentDanger),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.accentDanger)),
              ),
            ],
            if (_verificationResult != null) ...[
              const SizedBox(height: 24),
              _buildResultCard(_verificationResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> res) {
    final status = res['status'] as String? ?? 'UNKNOWN';
    final isSuccess = status == 'CLAIMED_SUCCESSFULLY';

    return Card(
      color: isSuccess ? AppTheme.accentSuccess.withOpacity(0.15) : AppTheme.accentWarning.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isSuccess ? AppTheme.accentSuccess : AppTheme.accentWarning, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isSuccess ? Icons.check_circle : Icons.warning_amber_rounded, color: isSuccess ? AppTheme.accentSuccess : AppTheme.accentWarning, size: 28),
                const SizedBox(width: 10),
                Text(
                  isSuccess ? 'VERIFIED & CLAIMED!' : status,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isSuccess ? AppTheme.accentSuccess : AppTheme.accentWarning),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 24),
            if (res['player_display_name'] != null)
              Text('Winner: ${res['player_display_name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            if (res['prize_type'] != null)
              Text('Prize: ${Formatters.formatPrizeName(res['prize_type'])}', style: const TextStyle(fontSize: 14, color: AppTheme.secondaryColor)),
            const SizedBox(height: 6),
            if (res['message'] != null)
              Text('${res['message']}', style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
          ],
        ),
      ),
    );
  }
}
