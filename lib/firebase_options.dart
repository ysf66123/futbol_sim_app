import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyARrlNaL8_nxrEYkqf76oHotuswtbKhSDU',
    appId: '1:819714803926:web:15e35178b3b96ccd6ba177',
    messagingSenderId: '819714803926',
    projectId: 'futboll-694e5',
    authDomain: 'futboll-694e5.firebaseapp.com',
    databaseURL:
        'https://futboll-694e5-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'futboll-694e5.firebasestorage.app',
    measurementId: 'G-3PEENTDCL1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBhHdM63CdROibPN3VvC_grUGZKe0-esl4',
    appId: '1:819714803926:android:138d24dfcc726f7e6ba177',
    messagingSenderId: '819714803926',
    projectId: 'futboll-694e5',
    databaseURL:
        'https://futboll-694e5-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'futboll-694e5.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCSq9oLBc2YE2SblK2jbUyyw-8UT3hm9Wc',
    appId: '1:819714803926:ios:00b960463dc1c6b86ba177',
    messagingSenderId: '819714803926',
    projectId: 'futboll-694e5',
    databaseURL:
        'https://futboll-694e5-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'futboll-694e5.firebasestorage.app',
    iosBundleId: 'com.example.futbolSim',
  );
}
