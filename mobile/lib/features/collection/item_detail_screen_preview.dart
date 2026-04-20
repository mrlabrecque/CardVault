import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import 'item_detail_screen.dart';

const _baseCard = UserCard(
  id: 'preview-1',
  player: 'Connor Bedard',
  cardNumber: '201',
  sport: 'hockey',
  set: '2023-24 Upper Deck Series 1',
  year: 2023,
  parallel: 'Base',
  isGraded: false,
  rookie: true,
  autograph: false,
  memorabilia: false,
  ssp: false,
  pricePaid: 85.00,
  currentValue: 142.50,
);

const _gradedCard = UserCard(
  id: 'preview-2',
  player: 'Caitlin Clark',
  cardNumber: '1',
  sport: 'basketball',
  set: '2024 Prizm WNBA',
  year: 2024,
  parallel: 'Silver',
  serialMax: 99,
  serialNumber: '34',
  isGraded: true,
  grader: 'PSA',
  grade: '10',
  rookie: true,
  autograph: true,
  memorabilia: false,
  ssp: false,
  pricePaid: 320.00,
  currentValue: 475.00,
);

const _autoCard = UserCard(
  id: 'preview-3',
  player: 'Shohei Ohtani',
  cardNumber: 'BA-SO',
  sport: 'baseball',
  set: '2024 Topps Chrome',
  year: 2024,
  parallel: 'Gold Refractor',
  serialMax: 50,
  serialNumber: '12',
  isGraded: false,
  rookie: false,
  autograph: true,
  memorabilia: true,
  ssp: false,
  pricePaid: 1200.00,
  currentValue: 980.00,
);

Widget _wrap(UserCard card) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: ItemDetailScreen(card: card),
      ),
    );

@Preview(name: 'Base RC — hockey')
Widget previewBaseCard() => _wrap(_baseCard);

@Preview(name: 'Graded PSA 10 — basketball')
Widget previewGradedCard() => _wrap(_gradedCard);

@Preview(name: 'Auto Patch — baseball (loss)')
Widget previewAutoCard() => _wrap(_autoCard);

@Preview(name: 'Dark mode — RC')
Widget previewDarkCard() => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true, brightness: Brightness.dark),
        home: ItemDetailScreen(card: _baseCard),
      ),
    );
