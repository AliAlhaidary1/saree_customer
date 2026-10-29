import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Destinations rendered by the root `ShellRoute`.
///
/// Pushing one of these from a standalone page makes go_router build a second
/// shell page, whose key is based on the shell route hash. The Navigator then
/// asserts on the duplicated page key, so tab destinations must use `go`.
const Set<String> shellBranchPaths = {
  '/',
  '/products',
  '/haraj',
  '/orders',
  '/akhdimni',
};

bool isShellBranchLocation(String location) {
  final path = Uri.tryParse(location.trim())?.path;
  return path != null && shellBranchPaths.contains(path);
}

String _target(String location) {
  final trimmed = location.trim();
  return trimmed.isEmpty ? '/' : trimmed;
}

/// Navigation entry point for a location that may point at a shell branch.
void openAppLocation(BuildContext context, String location) {
  final target = _target(location);
  if (isShellBranchLocation(target)) {
    context.go(target);
  } else {
    context.push(target);
  }
}

/// Same as [openAppLocation] for callers that only hold the router.
void openRouterLocation(GoRouter router, String location) {
  final target = _target(location);
  if (isShellBranchLocation(target)) {
    router.go(target);
  } else {
    router.push(target);
  }
}
