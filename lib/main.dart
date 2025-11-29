import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'package:flutter/painting.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:venom_canvas/src/presentation/bloc/desktop_manager_bloc.dart';
import 'package:venom_canvas/src/data/desktop_repository_impl.dart';
import 'package:venom_canvas/src/presentation/pages/desktop_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 1;
  PaintingBinding.instance.imageCache.maximumSize = 1;

  runApp(
    RepositoryProvider<DesktopRepositoryImpl>(
      create: (_) => DesktopRepositoryImpl(),
      child: BlocProvider(
        create: (ctx) =>
            DesktopManagerBloc(repository: ctx.read<DesktopRepositoryImpl>())
              ..add(LoadDesktopEvent()),
        child: const VenomDesktopApp(),
      ),
    ),
  );
}

class VenomDesktopApp extends StatelessWidget {
  const VenomDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Venom Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        fontFamily: 'Sans',
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF1F1F24),
          elevation: 10,
          shadowColor: Colors.black87,
          textStyle: TextStyle(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0x3322FFFF), width: 1),
          ),
        ),
      ),
      home: const DesktopPage(),
    );
  }
}
