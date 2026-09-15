import 'package:flutter/material.dart';
import '../theme/palette.dart';

class SongSearchField extends StatefulWidget {
  final CobblestonePalette palette;
  final ValueChanged<String> onChanged;
  final String hintText;

  const SongSearchField({
    super.key,
    required this.palette,
    required this.onChanged,
    this.hintText = 'Şarkı ara',
  });

  @override
  State<SongSearchField> createState() => _SongSearchFieldState();
}

class _SongSearchFieldState extends State<SongSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: p.mute),
          prefixIcon: Icon(Icons.search_rounded, color: p.mute),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.close_rounded, color: p.mute),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              );
            },
          ),
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.orange),
          ),
        ),
      ),
    );
  }
}

