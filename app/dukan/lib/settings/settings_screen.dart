import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/products/products_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _timezoneController;
  late String _currencyCode;
  late String _languageCode;
  late Future<_SettingsReferenceData> _refsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop.name);
    _timezoneController = TextEditingController(text: widget.shop.timezone);
    _currencyCode = widget.shop.currencyCode;
    _languageCode = widget.shop.defaultLanguageCode;
    final api = context.read<ShopApi>();
    _refsFuture = Future.wait([api.listCurrencies(), api.listLanguages()])
        .then(
          (results) => _SettingsReferenceData(
            currencies: results[0],
            languages: results[1],
          ),
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final l = tr(context);
    final api = context.read<ShopApi>();
    final auth = context.read<AuthController>();
    try {
      await api.updateShopDefaults(
        shopId: widget.shop.id,
        name: _nameController.text,
        currencyCode: _currencyCode,
        defaultLanguageCode: _languageCode,
        timezone: _timezoneController.text,
      );
      await auth.refreshSelectedShop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsSavedToast)),
      );
      Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) {
        showError(context, l.settingsSaveFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.settingsTitle),
      body: SafeArea(
        child: FutureBuilder<_SettingsReferenceData>(
          future: _refsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(child: Text(l.settingsSaveFailedMessage));
            }
            final refs = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l.settingsShopNameLabel),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _currencyCode,
                  decoration: InputDecoration(
                    labelText: l.settingsCurrencyLabel,
                  ),
                  items: [
                    for (final c in refs.currencies)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} (${c.label})'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _currencyCode = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _languageCode,
                  decoration: InputDecoration(
                    labelText: l.settingsLanguageLabel,
                  ),
                  items: [
                    for (final lang in refs.languages)
                      DropdownMenuItem(
                        value: lang.code,
                        child: Text(lang.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _languageCode = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _timezoneController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l.settingsTimezoneLabel,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(l.settingsSaveButton),
                ),
                const SizedBox(height: 28),
                const Divider(),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    minVerticalPadding: 18,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(
                      l.productsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final auth = context.read<AuthController>();
                      final api = context.read<ShopApi>();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MultiProvider(
                            providers: [
                              ChangeNotifierProvider<AuthController>.value(
                                value: auth,
                              ),
                              Provider<ShopApi>.value(value: api),
                            ],
                            child: ProductsScreen(shop: widget.shop),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsReferenceData {
  const _SettingsReferenceData({
    required this.currencies,
    required this.languages,
  });

  final List<ReferenceOption> currencies;
  final List<ReferenceOption> languages;
}
