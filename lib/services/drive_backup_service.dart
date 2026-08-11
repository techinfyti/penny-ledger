import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class DriveBackupService {
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DriveBackupService(this._googleSignIn);

  static const _backupFileName = 'pennyledger_backup.json';

  Future<drive.DriveApi> _driveApi() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      throw Exception('Unable to authenticate with Google Drive. Please sign in again.');
    }
    return drive.DriveApi(client);
  }

  Future<String?> _findBackupFileId(drive.DriveApi api) async {
    final result = await api.files.list(
      q: "name = '$_backupFileName' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, modifiedTime)',
    );
    if (result.files == null || result.files!.isEmpty) return null;
    return result.files!.first.id;
  }

  Future<Map<String, dynamic>> _buildBackupPayload(String uid) async {
    final expensesSnap = await _db.collection('users').doc(uid).collection('expenses').get();
    final expenses = expensesSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final date = data['date'];
      if (date is Timestamp) data['date'] = date.toDate().toIso8601String();
      data.remove('createdAt');
      return data;
    }).toList();

    final categoriesDoc = await _db.collection('users').doc(uid).collection('meta').doc('categories').get();

    final budgetsSnap = await _db.collection('users').doc(uid).collection('budgets').get();
    final budgets = {for (final doc in budgetsSnap.docs) doc.id: doc.data()};

    final recurringSnap = await _db.collection('users').doc(uid).collection('recurring').get();
    final recurring = recurringSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      data.remove('createdAt');
      return data;
    }).toList();

    final accountsSnap = await _db.collection('users').doc(uid).collection('accounts').get();
    final accounts = accountsSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) data['createdAt'] = createdAt.toDate().toIso8601String();
      return data;
    }).toList();

    final groupsSnap = await _db.collection('users').doc(uid).collection('groups').get();
    final groups = groupsSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) data['createdAt'] = createdAt.toDate().toIso8601String();
      return data;
    }).toList();

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'expenses': expenses,
      'categories': categoriesDoc.data() ?? {},
      'budgets': budgets,
      'recurring': recurring,
      'accounts': accounts,
      'groups': groups,
    };
  }

  Future<DateTime> backup(String uid) async {
    final api = await _driveApi();
    final payload = await _buildBackupPayload(uid);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final media = drive.Media(Stream.value(bytes), bytes.length);

    final existingId = await _findBackupFileId(api);
    if (existingId != null) {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      final file = drive.File()
        ..name = _backupFileName
        ..mimeType = 'application/json';
      await api.files.create(file, uploadMedia: media);
    }
    return DateTime.now();
  }

  Future<bool> hasBackup() async {
    final api = await _driveApi();
    return await _findBackupFileId(api) != null;
  }

  Future<void> restore(String uid) async {
    final api = await _driveApi();
    final fileId = await _findBackupFileId(api);
    if (fileId == null) {
      throw Exception('No backup found in Google Drive.');
    }

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    final expensesRef = _db.collection('users').doc(uid).collection('expenses');
    final expenses = (payload['expenses'] as List? ?? []);
    for (final raw in expenses) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      final dateStr = data['date'] as String?;
      if (dateStr != null) data['date'] = Timestamp.fromDate(DateTime.parse(dateStr));
      data['createdAt'] = FieldValue.serverTimestamp();
      await expensesRef.doc(id).set(data);
    }

    final categories = payload['categories'] as Map<String, dynamic>?;
    if (categories != null && categories.isNotEmpty) {
      await _db.collection('users').doc(uid).collection('meta').doc('categories').set(categories);
    }

    final budgets = payload['budgets'] as Map<String, dynamic>? ?? {};
    for (final entry in budgets.entries) {
      await _db
          .collection('users')
          .doc(uid)
          .collection('budgets')
          .doc(entry.key)
          .set(Map<String, dynamic>.from(entry.value as Map));
    }

    final recurringRef = _db.collection('users').doc(uid).collection('recurring');
    final recurring = (payload['recurring'] as List? ?? []);
    for (final raw in recurring) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      await recurringRef.doc(id).set(data);
    }

    final accountsRef = _db.collection('users').doc(uid).collection('accounts');
    final accounts = (payload['accounts'] as List? ?? []);
    for (final raw in accounts) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      await accountsRef.doc(id).set(data);
    }

    final groupsRef = _db.collection('users').doc(uid).collection('groups');
    final groups = (payload['groups'] as List? ?? []);
    for (final raw in groups) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      await groupsRef.doc(id).set(data);
    }
  }
}
