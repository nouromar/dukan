import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/settings/about_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/voided_visibility.dart';

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
  // Device-level display pref (default show). Loaded async; toggling it writes
  // through immediately, independent of the Save button.
  bool _showVoided = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShowVoided());
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
        )
        // Offline (reference lists uncached this session): still open the
        // form with the shop's current currency + language as the only
        // options, so name / timezone stay editable. Currency is locked
        // after the first sale anyway, and changing it needs a connection.
        .catchError(
          (Object _, StackTrace __) => _SettingsReferenceData(
            currencies: [
              ReferenceOption(code: _currencyCode, label: _currencyCode),
            ],
            languages: [
              ReferenceOption(code: _languageCode, label: _languageCode),
            ],
          ),
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _loadShowVoided() async {
    final show = await VoidedVisibility.showVoided();
    if (mounted && show != _showVoided) setState(() => _showVoided = show);
  }

  void _toggleShowVoided(bool value) {
    setState(() => _showVoided = value);
    unawaited(VoidedVisibility.setShowVoided(value));
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
        // A shop with recorded transactions can't change currency (locked
        // server-side in 0081). Surface the reason, not a generic failure.
        final changedCurrency = _currencyCode != widget.shop.currencyCode;
        showError(
          context,
          changedCurrency
              ? l.settingsCurrencyLockedMessage
              : l.settingsSaveFailedMessage,
        );
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
            // Currency is a setup-time decision. Once the shop is set up, it's
            // locked in Settings (the server also hard-locks it after the first
            // transaction, 0081; support/admin can still change it pre-sale).
            final currencyLocked = widget.shop.setupStatus != 'not_started';
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
                    helperText:
                        currencyLocked ? l.settingsCurrencyLockedHint : null,
                  ),
                  items: [
                    for (final c in refs.currencies)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} (${c.label})'),
                      ),
                  ],
                  // null onChanged disables the field once the shop is set up.
                  onChanged: currencyLocked
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _currencyCode = value);
                          }
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(l.settingsSaveButton),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_outlined),
                  title: Text(l.settingsShowVoidedTitle),
                  subtitle: Text(l.settingsShowVoidedSubtitle),
                  value: _showVoided,
                  onChanged: _toggleShowVoided,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(l.settingsAboutRow),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
