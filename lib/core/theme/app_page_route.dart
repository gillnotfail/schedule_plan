import 'package:flutter/material.dart';

import 'package:schedule_plan/core/theme/app_motion.dart';

/// 统一页面转场。
///
/// M3 Expressive：页面进入使用 **Spatial Spring**（位移 + 轻微过冲），
/// 同时叠加 Effects Spring 的透明度渐变，避免"硬切"的廉价感。
///
/// 全 App 的 `Navigator.push` 一律走这里，禁止再直接 new MaterialPageRoute。
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required this.child,
    super.settings,
  }) : super(
          transitionDuration: AppMotion.pageTransition,
          reverseTransitionDuration: AppMotion.standard,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // 新页面：从下方 24dp 处带弹性上移 + 淡入
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: AppMotion.expressive,
                reverseCurve: AppMotion.exit,
              ),
            );
            final fade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.7, curve: AppMotion.enter),
              reverseCurve: AppMotion.exit,
            );
            final scale = Tween<double>(begin: 0.97, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: AppMotion.expressive),
            );
            // 旧页面：轻微后退 + 变暗，形成层次
            final outgoing = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(0, -0.02),
            ).animate(
              CurvedAnimation(
                parent: secondaryAnimation,
                curve: AppMotion.exit,
              ),
            );
            return SlideTransition(
              position: outgoing,
              child: FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: scale,
                  child: SlideTransition(position: slide, child: child),
                ),
              ),
            );
          },
        );

  final Widget child;
}

/// 便捷入口：以统一转场推送页面。
Future<T?> pushAppPage<T>(
  BuildContext context,
  Widget child, {
  RouteSettings? settings,
}) {
  return Navigator.of(context).push<T>(
    AppPageRoute<T>(child: child, settings: settings),
  );
}
