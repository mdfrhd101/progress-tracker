import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../theme/app_theme.dart';

/// User-adjustable look & feel, persisted in the `prefs` table.
class SettingsState extends Equatable {
  final Color accent;
  final String? fontFamily; // null = platform default
  final double textScale; // 0.9 / 1.0 / 1.15
  final bool loaded;

  const SettingsState({
    this.accent = AppColors.defaultAccent,
    this.fontFamily,
    this.textScale = 1.0,
    this.loaded = false,
  });

  SettingsState copyWith({
    Color? accent,
    String? fontFamily,
    bool clearFont = false,
    double? textScale,
    bool? loaded,
  }) =>
      SettingsState(
        accent: accent ?? this.accent,
        fontFamily: clearFont ? null : (fontFamily ?? this.fontFamily),
        textScale: textScale ?? this.textScale,
        loaded: loaded ?? this.loaded,
      );

  @override
  List<Object?> get props => [accent, fontFamily, textScale, loaded];
}

class SettingsCubit extends Cubit<SettingsState> {
  static const _kAccent = 'accent_color';
  static const _kFont = 'font_family';
  static const _kScale = 'text_scale';

  static const List<double> textScales = [0.9, 1.0, 1.15];

  final DatabaseHelper _db;

  SettingsCubit({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper.instance,
        super(const SettingsState());

  Future<void> load() async {
    final accentStr = await _db.getPref(_kAccent);
    final font = await _db.getPref(_kFont);
    final scaleStr = await _db.getPref(_kScale);
    if (isClosed) return;

    final accentValue = accentStr == null ? null : int.tryParse(accentStr);
    final scale = scaleStr == null ? null : double.tryParse(scaleStr);
    emit(SettingsState(
      accent:
          accentValue == null ? AppColors.defaultAccent : Color(accentValue),
      fontFamily: (font == null || font.isEmpty) ? null : font,
      textScale: scale ?? 1.0,
      loaded: true,
    ));
  }

  Future<void> setAccent(Color c) async {
    emit(state.copyWith(accent: c));
    await _db.setPref(_kAccent, '${c.toARGB32()}');
  }

  Future<void> setFont(String? family) async {
    emit(state.copyWith(fontFamily: family, clearFont: family == null));
    await _db.setPref(_kFont, family ?? '');
  }

  Future<void> setTextScale(double s) async {
    emit(state.copyWith(textScale: s));
    await _db.setPref(_kScale, '$s');
  }

  Future<void> reset() async {
    emit(const SettingsState(loaded: true));
    await _db.setPref(_kAccent, '${AppColors.defaultAccent.toARGB32()}');
    await _db.setPref(_kFont, '');
    await _db.setPref(_kScale, '1.0');
  }
}
