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
    final userRef = _db.collection('users').doc(uid);

    // The six collections below are independent reads — fetching them in
    // parallel instead of one-await-at-a-time cuts backup time to roughly
    // the slowest single read instead of the sum of all six.
    final results = await Future.wait([
      userRef.collection('expenses').get(),
      userRef.collection('meta').doc('categories').get(),
      userRef.collection('budgets').get(),
      userRef.collection('recurring').get(),
      userRef.collection('accounts').get(),
      userRef.collection('groups').get(),
    ]);

    final expensesSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final expenses = expensesSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final date = data['date'];
      if (date is Timestamp) data['date'] = date.toDate().toIso8601String();
      data.remove('createdAt');
      return data;
    }).toList();

    final categoriesDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

    final budgetsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final budgets = {for (final doc in budgetsSnap.docs) doc.id: doc.data()};

    final recurringSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final recurring = recurringSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      data.remove('createdAt');
      return data;
    }).toList();

    final accountsSnap = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final accounts = accountsSnap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) data['createdAt'] = createdAt.toDate().toIso8601String();
      return data;
    }).toList();

    final groupsSnap = results[5] as QuerySnapshot<Map<String, dynamic>>;
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
    final userRef = _db.collection('users').doc(uid);

    // A restore can involve hundreds of documents across five collections;
    // awaiting one write at a time made this take minutes. Queue every write
    // into batches instead (Firestore caps a batch at 500 operations) and
    // commit them in parallel.
    final writes = <_PendingWrite>[];

    final expensesRef = userRef.collection('expenses');
    final expenses = (payload['expenses'] as List? ?? []);
    for (final raw in expenses) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      final dateStr = data['date'] as String?;
      if (dateStr != null) data['date'] = Timestamp.fromDate(DateTime.parse(dateStr));
      data['createdAt'] = FieldValue.serverTimestamp();
      writes.add(_PendingWrite(expensesRef.doc(id), data));
    }

    final categories = payload['categories'] as Map<String, dynamic>?;
    if (categories != null && categories.isNotEmpty) {
      writes.add(_PendingWrite(userRef.collection('meta').doc('categories'), categories));
    }

    final budgetsRef = userRef.collection('budgets');
    final budgets = payload['budgets'] as Map<String, dynamic>? ?? {};
    for (final entry in budgets.entries) {
      writes.add(_PendingWrite(budgetsRef.doc(entry.key), Map<String, dynamic>.from(entry.value as Map)));
    }

    final recurringRef = userRef.collection('recurring');
    final recurring = (payload['recurring'] as List? ?? []);
    for (final raw in recurring) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      writes.add(_PendingWrite(recurringRef.doc(id), data));
    }

    final accountsRef = userRef.collection('accounts');
    final accounts = (payload['accounts'] as List? ?? []);
    for (final raw in accounts) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      writes.add(_PendingWrite(accountsRef.doc(id), data));
    }

    final groupsRef = userRef.collection('groups');
    final groups = (payload['groups'] as List? ?? []);
    for (final raw in groups) {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data.remove('id') as String;
      data['createdAt'] = FieldValue.serverTimestamp();
      writes.add(_PendingWrite(groupsRef.doc(id), data));
    }

    const chunkSize = 500;
    final commits = <Future<void>>[];
    for (var i = 0; i < writes.length; i += chunkSize) {
      final chunk = writes.skip(i).take(chunkSize);
      final batch = _db.batch();
      for (final write in chunk) {
        batch.set(write.ref, write.data);
      }
      commits.add(batch.commit());
    }
    await Future.wait(commits);
  }
}

class _PendingWrite {
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  _PendingWrite(this.ref, this.data);
}
