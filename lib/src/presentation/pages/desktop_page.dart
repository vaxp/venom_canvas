import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:venom_canvas/src/presentation/bloc/desktop_manager_bloc.dart';
import 'package:venom_canvas/src/presentation/views/desktop_view.dart';

class DesktopPage extends StatelessWidget {
  const DesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DesktopManagerBloc, DesktopManagerState>(
      builder: (context, state) {
        if (state is DesktopLoaded) {
          return DesktopView(
            entries: state.entries,
            wallpaperPath: state.wallpaperPath,
            positions: state.positions,
          );
        } else if (state is DesktopLoading || state is DesktopInitial) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (state is DesktopError) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: ${state.message}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => context.read<DesktopManagerBloc>().add(
                      LoadDesktopEvent(),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
