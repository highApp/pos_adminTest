import 'package:firebase_core/firebase_core.dart';

/// Firestore / network errors where retrying later is appropriate (e.g. device offline).
bool isFirestoreTransientOrOffline(Object error) {
  if (error is FirebaseException) {
    switch (error.code.toLowerCase()) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'aborted':
      case 'internal':
      case 'network-error':
      case 'network_error':
      case 'network-request-failed':
        return true;
      default:
        return false;
    }
  }
  final msg = error.toString().toLowerCase();
  return msg.contains('unavailable') && msg.contains('firestore');
}
