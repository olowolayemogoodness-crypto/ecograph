// ignore_for_file: prefer_const_constructors, use_super_parameters
import 'package:flutter/material.dart';

import 'eco_api.dart';
import 'intro.dart';
import 'theme.dart';

final EcoApi _api = EcoApi();

void main() => runApp(const EcoApp());

class EcoApp extends StatelessWidget {
  const EcoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EcoGraph',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SplashScreen(api: _api),
      );
}
