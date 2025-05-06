import 'package:flutter/material.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/utils/logo_service.dart';

class LogoPickerDialog extends StatefulWidget {
  final List<String> availableIssuers;
  final String? currentIssuer;

  const LogoPickerDialog({
    super.key,
    required this.availableIssuers,
    this.currentIssuer,
  });

  @override
  State<LogoPickerDialog> createState() => _LogoPickerDialogState();
}

class _LogoPickerDialogState extends State<LogoPickerDialog> {
  late TextEditingController _searchController;
  List<String> _filteredIssuers = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredIssuers = widget.availableIssuers;
    _searchController.addListener(_filterIssuers);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterIssuers);
    _searchController.dispose();
    super.dispose();
  }

  void _filterIssuers() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredIssuers = widget.availableIssuers;
      });
    } else {
      setState(() {
        _filteredIssuers =
            widget.availableIssuers
                .where((issuer) => issuer.toLowerCase().contains(query))
                .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Service Logo'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search service...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child:
                  _filteredIssuers.isEmpty
                      ? const Center(child: Text('No services found.'))
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredIssuers.length,
                        itemBuilder: (context, index) {
                          final issuer = _filteredIssuers[index];
                          final logoPath = LogoService.instance.getLogoPath(
                            issuer,
                          );
                          return ListTile(
                            leading: SizedBox(
                              width: 40,
                              height: 40,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4.0),
                                child: Image.asset(
                                  logoPath,
                                  fit: BoxFit.contain,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const Icon(
                                            Icons.business_center_outlined,
                                            size: 24,
                                          ),
                                ),
                              ),
                            ),
                            title: Text(issuer),
                            onTap: () {
                              Navigator.of(context).pop(issuer);
                            },
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop(); // Pop without a value
          },
        ),
      ],
    );
  }
}
