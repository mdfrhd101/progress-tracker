import 'package:flutter_test/flutter_test.dart';
import 'package:progress_tracker/services/update_service.dart';

/// Verifies the semver-ish comparison the in-app updater uses to decide
/// whether a GitHub release is newer than the installed version.
void main() {
  bool newer(String a, String b) => UpdateServiceTestHook.isNewer(a, b);

  test('detects a strictly newer version', () {
    expect(newer('1.4.0', '1.3.0'), isTrue);
    expect(newer('1.3.1', '1.3.0'), isTrue);
    expect(newer('2.0.0', '1.9.9'), isTrue);
    expect(newer('1.10.0', '1.9.0'), isTrue); // numeric, not lexicographic
  });

  test('same or older is not an update', () {
    expect(newer('1.3.0', '1.3.0'), isFalse);
    expect(newer('1.2.9', '1.3.0'), isFalse);
    expect(newer('1.3.0', '1.4.0'), isFalse);
  });
}
