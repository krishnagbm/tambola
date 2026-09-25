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
  final String currencyCode;
  final String currencySymbol;

  const BrandGiftPickerDialog({
    super.key,
    required this.prizeKey,
    required this.prizeLabel,
    this.targetBudgetValue,
    this.currentSelection,
    this.currencyCode = 'USD',
    this.currencySymbol = '\$',
  });

  static Future<BrandGiftSelectionResult?> show(
    BuildContext context, {
    required String prizeKey,
    required String prizeLabel,
    double? targetBudgetValue,
    BrandOffer? currentSelection,
    String currencyCode = 'USD',
    String currencySymbol = '\$',
  }) {
    return showDialog<BrandGiftSelectionResult>(
      context: context,
      builder: (_) => BrandGiftPickerDialog(
        prizeKey: prizeKey,
        prizeLabel: prizeLabel,
        targetBudgetValue: targetBudgetValue,
        currentSelection: currentSelection,
        currencyCode: currencyCode,
        currencySymbol: currencySymbol,
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
  bool _isCustomMode = false;

  // Custom Game-Exclusive Offer Controllers
  late final TextEditingController _customTitleController;
  late final TextEditingController _customBrandController;
  late final TextEditingController _customDomainController;
  late final TextEditingController _customValueController;
  late final TextEditingController _customUrlController;
  late final TextEditingController _customCodeController;
  String _customEmoji = '🎁';

  static const List<String> _emojiChoices = [
    '🎁',
    '🏆',
    '🛍️',
    '☕',
    '🍫',
    '🎧',
    '🍾',
    '🎟️',
    '💎',
    '🍕',
  ];

  bool get _isRowLine =>
      widget.prizeKey == 'TOP_LINE' ||
      widget.prizeKey == 'MIDDLE_LINE' ||
      widget.prizeKey == 'BOTTOM_LINE';

  String get _sym => widget.currencySymbol;

  double get _currencyMultiplier {
    switch (widget.currencyCode.toUpperCase()) {
      case 'INR':
        return 50.0; // Clean local gift card tiers ($10 -> ₹500, $25 -> ₹1250)
      case 'GBP':
        return 0.8;
      case 'EUR':
        return 1.0;
      case 'CAD':
        return 1.4;
      case 'AUD':
        return 1.5;
      case 'AED':
        return 4.0;
      case 'SGD':
        return 1.4;
      default:
        return 1.0;
    }
  }

  double _localizeOfferPrice(BrandOffer offer, double basePrice) {
    if (offer.isCustomHostOffer ||
        offer.currency.toUpperCase() == widget.currencyCode.toUpperCase()) {
      return basePrice;
    }
    final raw = basePrice * _currencyMultiplier;
    if (raw >= 100) {
      return (raw / 50).round() * 50.0;
    } else if (raw >= 20) {
      return (raw / 5).round() * 5.0;
    }
    return raw.roundToDouble();
  }

  @override
  void initState() {
    super.initState();
    final cur = widget.currentSelection;
    final isExistingCustom = cur != null && cur.isCustomHostOffer;
    _isCustomMode = isExistingCustom;
    _customEmoji = isExistingCustom ? cur.emoji : '🎁';
    _customTitleController = TextEditingController(
      text: isExistingCustom ? cur.productTitle : '',
    );
    _customBrandController = TextEditingController(
      text: isExistingCustom ? cur.brandName : '',
    );
    _customDomainController = TextEditingController(
      text: isExistingCustom ? cur.brandDomain : '',
    );
    final initialValue = isExistingCustom
        ? cur.retailPrice
        : (widget.targetBudgetValue ?? 0);
    _customValueController = TextEditingController(
      text: initialValue > 0 ? initialValue.toStringAsFixed(0) : '',
    );
    _customUrlController = TextEditingController(
      text: isExistingCustom ? cur.productUrl : '',
    );
    _customCodeController = TextEditingController(
      text: isExistingCustom ? (cur.promoCode ?? '') : '',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customTitleController.dispose();
    _customBrandController.dispose();
    _customDomainController.dispose();
    _customValueController.dispose();
    _customUrlController.dispose();
    _customCodeController.dispose();
    super.dispose();
  }

  void _assignCustomGift() {
    final title = _customTitleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a Gift / Product Title for this prize.'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
      return;
    }

    final brand = _customBrandController.text.trim().isEmpty
        ? 'Host Exclusive'
        : _customBrandController.text.trim();
    final rawDomain = _customDomainController.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'^www\.'), '')
        .split('/')
        .first;
    final val =
        double.tryParse(_customValueController.text.trim()) ??
        (widget.targetBudgetValue ?? 0.0);
    final url = _customUrlController.text.trim();
    final code = _customCodeController.text.trim();

    // Auto-infer domain from product URL if domain wasn't explicitly typed
    String resolvedDomain = rawDomain;
    if (resolvedDomain.isEmpty && url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed != null && parsed.host.isNotEmpty) {
        resolvedDomain = parsed.host.replaceAll(RegExp(r'^www\.'), '');
      }
    }

    final customOffer = BrandOffer(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      brandName: brand,
      brandDomain: resolvedDomain,
      contactEmail: '',
      productTitle: title,
      category: 'Host Custom',
      productUrl: url,
      retailPrice: val,
      organizerPrice: val,
      discountPercent: 0,
      currency: widget.currencyCode,
      promoCode: code.isEmpty ? null : code,
      emoji: _customEmoji,
      badgeText: 'HOST EXCLUSIVE',
    );

    Navigator.of(context).pop(
      BrandGiftSelectionResult(
        offer: customOffer,
        applyToAllRowLines: _applyToAllLines,
      ),
    );
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
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 740),
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
                          'Assign Prize Gift • ${widget.prizeLabel}',
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
                              ? 'Target Prize Value: $_sym${widget.targetBudgetValue!.toStringAsFixed(0)} (${widget.currencyCode}) • Pick a Global Gift or Create Your Own'
                              : 'Pick a Global Gift Template (${widget.currencyCode}) or create your own Custom Gift exclusively for this game',
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
              const SizedBox(height: 12),

              // Mode Selector Tabs: Partner Catalog vs. Create Custom Gift (Exclusive to This Game)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => setState(() => _isCustomMode = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: !_isCustomMode
                                ? AppTheme.secondaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '🛍️ Global Partner Catalog',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: !_isCustomMode
                                  ? Colors.black
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => setState(() => _isCustomMode = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _isCustomMode
                                ? AppTheme.secondaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '✨ Create Your Own Offer (This Game Only)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _isCustomMode
                                  ? Colors.black
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_isRowLine) ...[
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
                          'Apply this Gift & Value to all 3 Row Lines (Top, Middle & Bottom Line)',
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
                const SizedBox(height: 10),
              ],

              if (_isCustomMode)
                Expanded(child: _buildCustomOfferForm())
              else ...[
                // Search & Price Filter Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search global brands or products (e.g. Amazon, Starbucks, JBL, Nike)...',
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
                            borderSide: const BorderSide(
                              color: Color(0xFF2E334D),
                            ),
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
                  child: Builder(
                    builder: (context) {
                      final lowBound = (15 * _currencyMultiplier).round();
                      final highBound = (25 * _currencyMultiplier).round();
                      final priceOptions = <Map<String, String>>[
                        {'key': 'All', 'label': 'All Prices'},
                        {'key': 'LOW', 'label': 'Under $_sym$lowBound'},
                        {'key': 'MID', 'label': '$_sym$lowBound–$_sym$highBound'},
                        {'key': 'HIGH', 'label': '$_sym$highBound+'},
                      ];
                      return Row(
                        children: [
                          for (final priceOpt in priceOptions) ...[
                            ChoiceChip(
                              label: Text(priceOpt['label']!),
                              selected: _selectedPriceFilter == priceOpt['key'],
                              onSelected: (_) => setState(
                                () => _selectedPriceFilter = priceOpt['key']!,
                              ),
                              selectedColor: AppTheme.secondaryColor.withValues(
                                alpha: 0.25,
                              ),
                              backgroundColor: AppTheme.darkSurface,
                              labelStyle: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _selectedPriceFilter == priceOpt['key']
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
                            'Streaming & Entertainment',
                            'Gourmet Hampers',
                            'Tech & Gadgets',
                          ]) ...[
                            FilterChip(
                              label: Text(cat == 'All' ? 'All Categories' : cat),
                              selected: _selectedCategory == cat,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = cat),
                              selectedColor: AppTheme.primaryLight.withValues(
                                alpha: 0.25,
                              ),
                              checkmarkColor: const Color(0xFF93C5FD),
                              backgroundColor: AppTheme.darkSurface,
                              labelStyle: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _selectedCategory == cat
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFFCBD5E1),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      );
                    },
                  ),
                ),
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
                        if (_selectedPriceFilter == 'LOW' &&
                            o.retailPrice >= 15) {
                          return false;
                        }
                        if (_selectedPriceFilter == 'MID' &&
                            (o.retailPrice < 15 || o.retailPrice > 25)) {
                          return false;
                        }
                        if (_selectedPriceFilter == 'HIGH' &&
                            o.retailPrice <= 25) {
                          return false;
                        }
                        if (query.isNotEmpty) {
                          final localVal = _localizeOfferPrice(o, o.retailPrice);
                          final hay =
                              '${o.brandName} ${o.productTitle} ${o.productDescription ?? ''} ${o.category} $_sym${localVal.toStringAsFixed(0)}'
                                  .toLowerCase();
                          if (!hay.contains(query)) return false;
                        }
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'No matching catalog offers found.',
                                style: TextStyle(color: Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (_searchController.text
                                          .trim()
                                          .isNotEmpty &&
                                      _customTitleController.text.isEmpty) {
                                    _customTitleController.text =
                                        _searchController.text.trim();
                                  }
                                  setState(() => _isCustomMode = true);
                                },
                                icon: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Create Your Own Custom Gift for This Game',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondaryColor,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
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
                          final localRetail = _localizeOfferPrice(
                            offer,
                            offer.retailPrice,
                          );
                          final tolerance = 5 * _currencyMultiplier;
                          final isBudgetMatch =
                              widget.targetBudgetValue != null &&
                              widget.targetBudgetValue! > 0 &&
                              (localRetail - widget.targetBudgetValue!).abs() <=
                                  tolerance;

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomOfferForm() {
    final previewDomain = _customDomainController.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'^www\.'), '')
        .split('/')
        .first;

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppTheme.secondaryColor,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Exclusive to Your Game: Define any gift, voucher, hamper, or product not in the catalog. It is saved only for this game—never added to the public database—and will appear in Winner Rewards & your Hall of Fame card!',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFE2E8F0),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Emoji Selector Row
            const Text(
              'Choose Gift Icon / Emoji:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojiChoices.map((emoji) {
                final selected = _customEmoji == emoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _customEmoji = emoji),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.secondaryColor.withValues(alpha: 0.25)
                          : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppTheme.secondaryColor
                            : const Color(0xFF2E334D),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 19)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Gift Title & Value
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _customTitleController,
                    style: const TextStyle(fontSize: 13.5, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Gift / Product Title *',
                      hintText:
                          'e.g. $_sym${(25 * _currencyMultiplier).round()} Local Bakery Hamper, AirTag, Team Swag Pack',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _customValueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.accentSuccess,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Prize Value ($_sym)',
                      prefixText: _sym,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Brand / Sponsor Name & Optional Domain with Live Logo Preview
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customBrandController,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Brand / Store / Sponsor Name (Optional)',
                      hintText: 'e.g. Amazon, Tanishq, Rapid Consulting',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _customDomainController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Brand Website Domain (Optional Logo)',
                      hintText: 'e.g. amazon.in, apple.com',
                      isDense: true,
                    ),
                  ),
                ),
                if (previewDomain.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  CompanyLogo(
                    domain: previewDomain,
                    size: 38,
                    isCommercialUse: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Product / Gift Web Link
            TextField(
              controller: _customUrlController,
              style: const TextStyle(fontSize: 13, color: Color(0xFF38BDF8)),
              decoration: const InputDecoration(
                labelText:
                    'Product / Gift Link (Optional — Clickable on Hall of Fame & Winner Rewards)',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            // Optional Voucher / Promo Code
            TextField(
              controller: _customCodeController,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText:
                    'Voucher / Promo Code or Claim Note (Optional — Can also be added at Prize Settlement)',
                hintText: 'e.g. WINNER-2026 or Leave blank to enter at settlement',
                isDense: true,
              ),
            ),
            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isCustomMode = false),
                  child: const Text('Back to Partner Catalog'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _assignCustomGift,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    _applyToAllLines && _isRowLine
                        ? 'Assign Custom Gift to All 3 Row Lines'
                        : 'Assign Custom Gift to ${widget.prizeLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard(
    BrandOffer offer, {
    required bool isSelected,
    required bool isBudgetMatch,
  }) {
    final localRetail = _localizeOfferPrice(offer, offer.retailPrice);
    final localOrg = _localizeOfferPrice(offer, offer.organizerPrice);
    final isFreeSponsored = offer.organizerPrice == 0;
    final isTemplate = offer.isHostSelfFulfilledTemplate;

    String priceSummaryText;
    if (isFreeSponsored) {
      priceSummaryText =
          'Value: $_sym${localRetail.toStringAsFixed(0)} • 100% FREE FOR HOST';
    } else if (isTemplate) {
      priceSummaryText =
          'Suggested Value: $_sym${localRetail.toStringAsFixed(0)} • Host provides code at settlement';
    } else if (localOrg < localRetail) {
      priceSummaryText =
          'Value: $_sym${localRetail.toStringAsFixed(0)} • Host Deal: $_sym${localOrg.toStringAsFixed(0)}';
    } else {
      priceSummaryText = 'Prize Value: $_sym${localRetail.toStringAsFixed(0)}';
    }

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
                        priceSummaryText,
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
              final localizedOffer = BrandOffer(
                id: offer.id,
                brandName: offer.brandName,
                brandDomain: offer.brandDomain,
                brandLogoUrl: offer.brandLogoUrl,
                contactName: offer.contactName,
                contactEmail: offer.contactEmail,
                productTitle: offer.productTitle,
                productDescription: offer.productDescription,
                category: offer.category,
                productImageUrl: offer.productImageUrl,
                productUrl: offer.productUrl,
                retailPrice: localRetail,
                organizerPrice: localOrg,
                discountPercent: offer.discountPercent,
                currency: widget.currencyCode,
                promoCode: offer.promoCode,
                emoji: offer.emoji,
                badgeText: offer.badgeText,
                status: offer.status,
                gamesAssignedCount: offer.gamesAssignedCount,
                clicksCount: offer.clicksCount,
              );
              Navigator.of(context).pop(
                BrandGiftSelectionResult(
                  offer: localizedOffer,
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
