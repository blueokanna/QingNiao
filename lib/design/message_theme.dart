import 'package:flutter/material.dart';

abstract final class MessageMotion {
  static const duration = Duration(milliseconds: 360);
  static const curve = Curves.easeInOutCubicEmphasized;
  static Duration of(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

ThemeData messageTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff416b53),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const StadiumBorder(),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: MessagePageTransition(),
        TargetPlatform.iOS: MessagePageTransition(),
      },
    ),
  );
}

class MessagePageTransition extends PageTransitionsBuilder {
  const MessagePageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: MessageMotion.curve));
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: progress.drive(
          Tween(begin: const Offset(0, .035), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}

class SenderAvatar extends StatelessWidget {
  const SenderAvatar({super.key, required this.address, this.size = 52});
  final String address;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(size * .44),
        topRight: Radius.circular(size * .44),
        bottomLeft: Radius.circular(size * .44),
        bottomRight: Radius.circular(size * .16),
      ),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.forum_outlined,
      color: Theme.of(context).colorScheme.onSecondaryContainer,
    ),
  );
}

String messageTime(int milliseconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.year == now.year ? '' : '${date.year}/'}${date.month}/${date.day}';
}
