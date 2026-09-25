import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/company_logo.dart';
import '../../../models/brand_offer.dart';
import '../../../providers/app_providers.dart';

class BrandGiftSelectionResult {
  final BrandOffer? offer;
  final bool applyToAllRowLines;
  final bool cleared;

  const BrandGiftSelectionResult({
    this.offer,
    this.applyToAllRowLines = false,
    this.cleared = false,
  });
}

class BrandGiftPickerDialog extends ConsumerStatefulWidget {
  final String prizeKey;
  final String prizeLabel;
  final double? targetBudgetValue;
  final BrandOffer? currentSelection;

  const BrandGiftPickerDialog({
    super.key,
    required this.prizeKey,
    required this.prizeLabel,
    this.targetBudgetValue,
    this.currentSelection,
  });

  static Future<BrandGiftSelectionResult?> show(
    BuildContext context, {
    required String prizeKey,
    required String prizeLabel,
    double? targetBudgetValue,
    BrandOffer? currentSelection,
  }) {
    return showDialog<BrandGiftSelectionResult>(
      context: context,
      builder: (_) => BrandGiftPickerDialog(
        prizeKey: prizeKey,
        prizeLabel: prizeLabel,
        targetBudgetValue: targetBudgetValue,
        currentSelection: currentSelection,
      ),
    );
  }

  @override
  ConsumerState<BrandGiftPickerDialog> createState() =>
      _BrandGiftPickerDialogState();
}

class _BrandGiftPickerDialogState extends ConsumerState<BrandGiftPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _selectedPriceFilter = 'All';
  bool _applyToAllLines = false;

  bool get _isRowLine =>
      widget.prizeKey == 'TOP_LINE' ||
      widget.prizeKey == 'MIDDLE_LINE' ||
      widget.prizeKey == 'BOTTOM_LINE';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offersAsync = ref.watch(activeBrandOffersProvider);
    final query = _searchController.text.trim().toLowerCase();

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: AppTheme.secondaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assign Brand Gift • ${widget.prizeLabel}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.targetBudgetValue != null &&
                                  widget.targetBudgetValue! > 0
                              ? 'Target Prize Value: \$${widget.targetBudgetValue!.toStringAsFixed(0)} • Browse discounted Brand Partner offers'
                              : 'Select a sponsored Brand Gift to award this prize winner & showcase on Hall of Fame',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.currentSelection != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(
                        const BrandGiftSelectionResult(cleared: true),
                      ),
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 16,
                        color: AppTheme.accentDanger,
                      ),
                      label: const Text(
                        'Remove Gift',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.accentDanger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search & Price Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13.5, color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            'Search by brand, product, or keyword (e.g. Starbucks, Speaker, \$25)...',
                        hintStyle: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: Color(0xFF94A3B8),
                        ),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.darkSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E334D)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Category + Price Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final priceOpt in [
                      'All',
                      'Under \$15',
                      '\$15–\$25',
                      '\$25+',
                    ]) ...[
                      ChoiceChip(
                        label: Text(priceOpt),
                        selected: _selectedPriceFilter == priceOpt,
                        onSelected: (_) =>
                            setState(() => _selectedPriceFilter = priceOpt),
                        selectedColor:
                            AppTheme.secondaryColor.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.darkSurface,
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _selectedPriceFilter == priceOpt
                              ? AppTheme.secondaryColor
                              : const Color(0xFFCBD5E1),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                    ],
                    const SizedBox(width: 6),
                    for (final cat in [
                      'All',
                      'Coffee & Dining',
                      'Shopping Vouchers',
                      'Gourmet Hampers',
                      'Tech & Gadgets',
                      'Beauty & Lifestyle',
                    ]) ...[
                      FilterChip(
                        label: Text(cat == 'All' ? 'All Categories' : cat),
                        selected: _selectedCategory == cat,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = cat),
                        selectedColor:
                            AppTheme.primaryLight.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.darkSurface,
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _selectedCategory == cat
                              ? AppTheme.primaryLight
                              : const Color(0xFF94A3B8),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),

              if (_isRowLine) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primaryLight.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _applyToAllLines,
                          activeColor: AppTheme.secondaryColor,
                          onChanged: (v) =>
                              setState(() => _applyToAllLines = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Apply this selected Brand Gift & Value to all 3 Row Lines (Top, Middle & Bottom Line)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Offers List
              Expanded(
                child: offersAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      'Could not load Brand Gift catalog: $err',
                      style: const TextStyle(color: AppTheme.accentDanger),
                    ),
                  ),
                  data: (offers) {
                    final filtered = offers.where((o) {
                      if (_selectedCategory != 'All' &&
                          o.category.toLowerCase() !=
                              _selectedCategory.toLowerCase()) {
                        return false;
                      }
                      if (_selectedPriceFilter == 'Under \$15' &&
                          o.retailPrice >= 15) {
                        return false;
                      }
                      if (_selectedPriceFilter == '\$15–\$25' &&
                          (o.retailPrice < 15 || o.retailPrice > 25)) {
                        return false;
                      }
                      if (_selectedPriceFilter == '\$25+' &&
                          o.retailPrice <= 25) {
                        return false;
                      }
                      if (query.isNotEmpty) {
                        final hay =
                            '${o.brandName} ${o.productTitle} ${o.productDescription ?? ''} ${o.category} \$${o.retailPrice.toStringAsFixed(0)}'
                                .toLowerCase();
                        if (!hay.contains(query)) return false;
                      }
                      return true;
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'No matching Brand Gift offers found. Try clearing filters.',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final offer = filtered[idx];
                        final isSelected =
                            widget.currentSelection?.id == offer.id;
                        final isBudgetMatch =
                            widget.targetBudgetValue != null &&
                            widget.targetBudgetValue! > 0 &&
                            (offer.retailPrice - widget.targetBudgetValue!)
                                    .abs() <=
                                5;

                        return _buildOfferCard(
                          offer,
                          isSelected: isSelected,
                          isBudgetMatch: isBudgetMatch,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferCard(
    BrandOffer offer, {
    required bool isSelected,
    required bool isBudgetMatch,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.secondaryColor.withValues(alpha: 0.12)
            : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.secondaryColor
              : (isBudgetMatch
                    ? AppTheme.accentSuccess.withValues(alpha: 0.6)
                    : const Color(0xFF2E334D)),
          width: isSelected || isBudgetMatch ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompanyLogo(
            domain: offer.brandDomain,
            size: 46,
            isCommercialUse: true,
            fallbackWidget: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(offer.emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      offer.brandName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    if (offer.badgeText != null &&
                        offer.badgeText!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPartyPurple.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          offer.badgeText!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFC4B5FD),
                          ),
                        ),
                      ),
                    if (isBudgetMatch)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSuccess.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '✨ MATCHES BUDGET',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentSuccess,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  offer.productTitle,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (offer.productDescription != null &&
                    offer.productDescription!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    offer.productDescription!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSuccess.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.accentSuccess.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        offer.organizerPrice < offer.retailPrice
                            ? 'Value: \$${offer.retailPrice.toStringAsFixed(0)} • Host Deal: \$${offer.organizerPrice.toStringAsFixed(2)}'
                            : 'Prize Value: \$${offer.retailPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentSuccess,
                        ),
                      ),
                    ),
                    if (offer.promoCode != null && offer.promoCode!.isNotEmpty)
                      Text(
                        'Code: ${offer.promoCode}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.tryParse(offer.productUrl);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Preview Product Page',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.primaryLight,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 12,
                            color: AppTheme.primaryLight,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop(
                BrandGiftSelectionResult(
                  offer: offer,
                  applyToAllRowLines: _applyToAllLines,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected
                  ? AppTheme.accentSuccess
                  : AppTheme.secondaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(
              isSelected ? Icons.check_circle_rounded : Icons.add_task_rounded,
              size: 16,
            ),
            label: Text(
              isSelected ? 'Selected' : 'Assign',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
