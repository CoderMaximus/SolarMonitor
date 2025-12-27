import 'package:flutter/material.dart';

// Define the enum in the same file
enum TransitionType {
  slideFromBottom,
  slideFromTop,
  slideFromRight,
  slideFromLeft,
  fade,
  scale,
  rotation,
  zoomIn,
}

class CustomPageRouter extends PageRouteBuilder {
  final Widget page;
  final TransitionType transitionType;
  final Duration duration;

  CustomPageRouter({
    required this.page,
    required this.transitionType,
    this.duration = const Duration(milliseconds: 300),
  }) : super(
         pageBuilder:
             (
               BuildContext context,
               Animation<double> animation,
               Animation<double> secondaryAnimation,
             ) => page,
         transitionDuration: duration,
         transitionsBuilder: (
           BuildContext context,
           Animation<double> animation,
           Animation<double> secondaryAnimation,
           Widget child,
         ) {
           switch (transitionType) {
             case TransitionType.slideFromTop:
               return _buildSlideTransitionFromTop(animation, child);
             case TransitionType.slideFromBottom:
               return _buildSlideTransitionFromBottom(animation, child);
             case TransitionType.slideFromLeft:
               return _buildSlideTransitionFromLeft(animation, child);
             case TransitionType.slideFromRight:
               return _buildSlideTransitionFromRight(animation, child);
             case TransitionType.fade:
               return _buildFadeTransition(animation, child);
             case TransitionType.scale:
               return _buildScaleTransition(animation, child);
             case TransitionType.rotation:
               return _buildRotationTransition(animation, child);
             case TransitionType.zoomIn:
               return _buildZoomInTransition(animation, child);
           }
         },
       );

  static Widget _buildSlideTransitionFromTop(
    Animation<double> animation,
    Widget child,
  ) {
    const begin = Offset(0.0, -1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    return SlideTransition(position: offsetAnimation, child: child);
  }

  static Widget _buildSlideTransitionFromBottom(
    Animation<double> animation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    return SlideTransition(position: offsetAnimation, child: child);
  }

  static Widget _buildSlideTransitionFromLeft(
    Animation<double> animation,
    Widget child,
  ) {
    const begin = Offset(-1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    return SlideTransition(position: offsetAnimation, child: child);
  }

  static Widget _buildSlideTransitionFromRight(
    Animation<double> animation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    return SlideTransition(position: offsetAnimation, child: child);
  }

  static Widget _buildFadeTransition(
    Animation<double> animation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget _buildScaleTransition(
    Animation<double> animation,
    Widget child,
  ) {
    return ScaleTransition(scale: animation, child: child);
  }

  static Widget _buildRotationTransition(
    Animation<double> animation,
    Widget child,
  ) {
    return RotationTransition(turns: animation, child: child);
  }

  static Widget _buildZoomInTransition(
    Animation<double> animation,
    Widget child,
  ) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
      child: child,
    );
  }
}
