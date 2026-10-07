import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/category.dart';

Color categoryDisplayColor(FinanceCategory category) =>
    category.colorArgb == null
        ? SomiaColors.muted
        : Color.lerp(Color(category.colorArgb!), Colors.white, 0.35)!;
