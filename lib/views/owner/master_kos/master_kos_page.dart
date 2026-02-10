import 'package:flutter/material.dart';

import 'kos_list_page.dart';

class MasterKosPage extends StatelessWidget {
  final String token;

  const MasterKosPage({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return KosListPage(token: token);
  }
}
