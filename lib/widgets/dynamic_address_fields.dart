import 'package:flutter/material.dart';

import '../core/json_util.dart';

class DynamicAddressFields extends StatefulWidget {
  const DynamicAddressFields({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<DynamicAddressFields> createState() => _DynamicAddressFieldsState();
}

class _DynamicAddressFieldsState extends State<DynamicAddressFields> {
  late Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.values);
  }

  @override
  void didUpdateWidget(covariant DynamicAddressFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields) {
      _values = _filterValues(widget.fields, _values);
      widget.onChanged(_values);
    }
  }

  Map<String, dynamic> _filterValues(
    List<Map<String, dynamic>> fields,
    Map<String, dynamic> current,
  ) {
    final allowed = fields.map((f) => J.str(f['field_key'])).toSet();
    return Map<String, dynamic>.fromEntries(
      current.entries.where((entry) => allowed.contains(entry.key)),
    );
  }

  void _setValue(String key, dynamic value) {
    setState(() {
      if (value == null || (value is String && value.trim().isEmpty)) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
      widget.onChanged(Map<String, dynamic>.from(_values));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fields.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: widget.fields.map((field) {
        final key = J.str(field['field_key']);
        final label = J.str(field['label']);
        final help = J.str(field['help_text']);
        final placeholder = J.str(field['placeholder']);
        final type = J.str(field['field_type']);
        final required = field['is_required'] == true;
        final options = (field['options'] as List?) ?? const [];

        Widget input;
        switch (type) {
          case 'textarea':
            input = TextFormField(
              key: ValueKey('textarea-$key'),
              initialValue: J.str(_values[key]),
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                hintText: placeholder.isEmpty ? null : placeholder,
                helperText: help.isEmpty ? null : help,
              ),
              onChanged: (value) => _setValue(key, value),
            );
            break;
          case 'number':
            input = TextFormField(
              key: ValueKey('number-$key'),
              initialValue: J.str(_values[key]),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                hintText: placeholder.isEmpty ? null : placeholder,
                helperText: help.isEmpty ? null : help,
              ),
              onChanged: (value) => _setValue(key, value),
            );
            break;
          case 'checkbox':
            input = CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _values[key] == true,
              onChanged: (checked) => _setValue(key, checked == true),
              title: Text(label),
              subtitle: help.isEmpty ? null : Text(help),
            );
            break;
          case 'select':
            final items = options
                .map((option) {
                  if (option is Map) {
                    return DropdownMenuItem<String>(
                      value: J.str(option['value']),
                      child: Text(J.str(option['label'] ?? option['value'])),
                    );
                  }
                  return DropdownMenuItem<String>(
                    value: J.str(option),
                    child: Text(J.str(option)),
                  );
                })
                .where((item) => item.value != null && item.value!.isNotEmpty)
                .toList();
            final current = _values[key]?.toString();
            final validValues = items.map((e) => e.value).toSet();
            input = DropdownButtonFormField<String>(
              key: ValueKey('select-$key'),
              initialValue:
                  current != null &&
                      current.isNotEmpty &&
                      validValues.contains(current)
                  ? current
                  : null,
              decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                helperText: help.isEmpty ? null : help,
              ),
              items: items,
              onChanged: (value) => _setValue(key, value),
            );
            break;
          default:
            input = TextFormField(
              key: ValueKey('text-$key'),
              initialValue: J.str(_values[key]),
              decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                hintText: placeholder.isEmpty ? null : placeholder,
                helperText: help.isEmpty ? null : help,
              ),
              onChanged: (value) => _setValue(key, value),
            );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: input,
        );
      }).toList(),
    );
  }
}
