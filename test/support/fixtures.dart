import 'dart:convert';
import 'dart:io';

import 'package:ganj/data/api/dto/poem.dart';

String fx(String name) => File('test/fixtures/$name.json').readAsStringSync();

Poem poem2130() => Poem.fromJson(jsonDecode(fx('poem_2130')) as Map<String, dynamic>);
Poem poem77000() => Poem.fromJson(jsonDecode(fx('poem_77000')) as Map<String, dynamic>);
