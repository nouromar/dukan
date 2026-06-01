import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ShopTypeSetupScreen extends StatefulWidget {
  const ShopTypeSetupScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ShopTypeSetupScreen> createState() => _ShopTypeSetupScreenState();
}

class _ShopTypeSetupScreenState extends State<ShopTypeSetupScreen> {
  late Future<List<TemplateOption>> _future;
  String? _selectedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<ShopApi>().listAvailableTemplates();
  }

  Future<void> _continue() async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _busy = true);
    final l = tr(context);
    final api = context.read<ShopApi>();
    final auth = context.read<AuthController>();
    try {
      await api.applyTemplate(shopId: widget.shop.id, templateId: id);
      if (!mounted) return;
      await api.completeSetup(shopId: widget.shop.id);
      await auth.refreshSelectedShop();
      // AuthRouter watches selectedShop.setupStatus and rebuilds into
      // HomeScreen automatically — nothing to navigate here.
    } on PostgrestException {
      if (mounted) {
        showError(context, l.applyTemplateFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    final l = tr(context);
    final api = context.read<ShopApi>();
    final auth = context.read<AuthController>();
    try {
      await api.completeSetup(shopId: widget.shop.id);
      await auth.refreshSelectedShop();
    } on PostgrestException {
      if (mounted) {
        showError(context, l.completeSetupFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final templateApplied = widget.shop.isTemplateApplied;

    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.setupStepTemplateTitle,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: () => context.read<AuthController>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: templateApplied
            ? _ResumeBody(
                shopName: widget.shop.name,
                busy: _busy,
                onFinish: _resume,
              )
            : _PickerBody(
                future: _future,
                selectedId: _selectedId,
                busy: _busy,
                onSelect: (v) => setState(() => _selectedId = v),
                onContinue: _continue,
              ),
      ),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.future,
    required this.selectedId,
    required this.busy,
    required this.onSelect,
    required this.onContinue,
  });

  final Future<List<TemplateOption>> future;
  final String? selectedId;
  final bool busy;
  final ValueChanged<String?> onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            l.setupStepTemplateBody,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<TemplateOption>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.applyTemplateFailedMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final options = snapshot.data ?? const <TemplateOption>[];
              if (options.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.templatesEmptyMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                );
              }
              return RadioGroup<String>(
                groupValue: selectedId,
                onChanged: (v) {
                  if (busy) return;
                  onSelect(v);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final opt = options[i];
                    final selected = selectedId == opt.id;
                    return Card(
                      elevation: selected ? 3 : 1,
                      child: RadioListTile<String>(
                        value: opt.id,
                        title: Text(
                          opt.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: selectedId == null || busy ? null : onContinue,
            child: busy
                ? const CircularProgressIndicator()
                : Text(l.applyTemplateButton),
          ),
        ),
      ],
    );
  }
}

class _ResumeBody extends StatelessWidget {
  const _ResumeBody({
    required this.shopName,
    required this.busy,
    required this.onFinish,
  });

  final String shopName;
  final bool busy;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.setupStepTemplateDone(shopName),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.setupStepFinishBody,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: busy ? null : onFinish,
            child: busy
                ? const CircularProgressIndicator()
                : Text(l.setupStepFinishButton),
          ),
        ),
      ],
    );
  }
}
