import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/drive.file'],
  );

  GoogleSignIn get googleSignIn => _googleSignIn;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Fires on sign-in/sign-out *and* whenever the signed-in user's profile
  /// data (name, email, photo) changes — the right stream to drive any UI
  /// that displays "who's logged in," since a plain one-time read of
  /// [currentUser] can catch a moment before Google's profile data has
  /// finished populating.
  Stream<User?> get userChanges => _auth.userChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await result.user?.reload();
    return result;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore Google-side sign-out failures (e.g. network blips) — the
      // Firebase sign-out below is what actually ends the app session.
    }
    await _auth.signOut();
  }
}
