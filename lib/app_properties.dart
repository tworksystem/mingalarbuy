import 'package:flutter/material.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';

// Legacy color references mapped to PlanetMM cool palette (no yellow/gold)
const Color yellow = AppTheme.brightBlue;
const Color mediumYellow = AppTheme.brightPurple;
const Color darkYellow = AppTheme.deepBlue;
const Color transparentYellow = Color.fromRGBO(33, 150, 243, 0.35);
const Color darkGrey = AppTheme.darkGrey;

// Updated main button gradient with PlanetMM colors
const LinearGradient mainButton = LinearGradient(
  colors: [
    AppTheme.deepBlue,
    AppTheme.mediumBlue,
    AppTheme.brightPurple,
  ],
  begin: FractionalOffset.topCenter,
  end: FractionalOffset.bottomCenter,
);

const List<BoxShadow> shadow = [
  BoxShadow(color: Colors.black12, offset: Offset(0, 3), blurRadius: 6)
];

double screenAwareSize(int size, BuildContext context) {
  double baseHeight = 640.0;
  return size * MediaQuery.of(context).size.height / baseHeight;
}