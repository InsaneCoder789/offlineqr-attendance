import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../sync/bootstrap_models.dart';
import '../../features/attendance/attendance_math.dart';

const int localSchemaVersion = 6;

class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.rollNumber,
    required this.displayName,
    required this.sectionCode,
  });

  final String id;
  final String rollNumber;
  final String displayName;
  final String sectionCode;
}

class CourseSummary {
  const CourseSummary({
    required this.courseCode,
    required this.courseName,
    required this.totalClasses,
    required this.present,
    required this.absent,
    required this.percentage,
  });

  final String courseCode;
  final String courseName;
  final int totalClasses;
  final int present;
  final int absent;
  final double percentage;
}

class AttendanceHistoryItem {
  const AttendanceHistoryItem({
    required this.courseCode,
    required this.scheduledStart,
    required this.status,
    required this.method,
  });

  final String courseCode;
  final String scheduledStart;
  final String status;
  final String? method;
}

class CourseAttendanceDetail {
  const CourseAttendanceDetail({
    required this.courseCode,
    required this.courseName,
    required this.present,
    required this.absent,
    required this.percentage,
    required this.history,
  });

  final String courseCode;
  final String courseName;
  final int present;
  final int absent;
  final double percentage;
  final List<AttendanceHistoryItem> history;
}

class TimetableItem {
  const TimetableItem({
    required this.courseCode,
    required this.courseName,
    required this.sectionCode,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  final String courseCode;
  final String courseName;
  final String sectionCode;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String room;
}

class CourseOfferingProjection {
  const CourseOfferingProjection({
    required this.courseOfferingId,
    required this.courseCode,
    required this.courseName,
    required this.sectionCode,
  });

  final String courseOfferingId;
  final String courseCode;
  final String courseName;
  final String sectionCode;
}

class DeviceRegistrationProjection {
  const DeviceRegistrationProjection({
    required this.deviceRegistrationId,
    required this.studentId,
    required this.status,
    required this.keyFingerprint,
    required this.platform,
    required this.displayLabel,
    required this.lastVerifiedAt,
    required this.serverVersion,
  });

  final String deviceRegistrationId;
  final String studentId;
  final String status;
  final String keyFingerprint;
  final String platform;
  final String? displayLabel;
  final String? lastVerifiedAt;
  final int serverVersion;
}

class AttendanceClaimProjection {
  const AttendanceClaimProjection({
    required this.claimId,
    required this.sessionId,
    required this.studentId,
    required this.deviceRegistrationId,
    required this.qrEpoch,
    required this.qrChallenge,
    required this.qrIssuedAt,
    required this.qrExpiresAt,
    required this.qrSignature,
    required this.qrCapturedAt,
    required this.claimCreatedAt,
    required this.claimExpiresAt,
    required this.claimState,
    required this.deviceSignature,
  });

  final String claimId;
  final String sessionId;
  final String studentId;
  final String deviceRegistrationId;
  final int qrEpoch;
  final String qrChallenge;
  final String qrIssuedAt;
  final String qrExpiresAt;
  final String qrSignature;
  final String qrCapturedAt;
  final String claimCreatedAt;
  final String claimExpiresAt;
  final String claimState;
  final String deviceSignature;
}

class AttendanceProofOutboxEntry {
  const AttendanceProofOutboxEntry({
    required this.id,
    required this.proofId,
    required this.sessionId,
    required this.studentId,
    required this.deviceRegistrationId,
    required this.payloadJson,
    required this.state,
    required this.attemptCount,
    required this.nextAttemptAt,
    required this.lastAttemptAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastErrorCode,
  });

  final String id;
  final String proofId;
  final String sessionId;
  final String studentId;
  final String deviceRegistrationId;
  final String payloadJson;
  final String state;
  final int attemptCount;
  final String? nextAttemptAt;
  final String? lastAttemptAt;
  final String createdAt;
  final String updatedAt;
  final String? lastErrorCode;
}

class AttendanceLogEntry {
  const AttendanceLogEntry({
    required this.proofId,
    required this.sessionId,
    required this.courseCode,
    required this.courseName,
    required this.sectionCode,
    required this.recordedAt,
    required this.claimState,
    required this.syncState,
    required this.attemptCount,
    required this.lastErrorCode,
  });

  final String proofId;
  final String sessionId;
  final String courseCode;
  final String courseName;
  final String sectionCode;
  final String recordedAt;
  final String claimState;
  final String syncState;
  final int attemptCount;
  final String? lastErrorCode;

  bool get hasDiscrepancy =>
      syncState == 'SERVER_REJECTED' || syncState == 'CONFLICT_REVIEW';

  bool get isServerAccepted => syncState == 'SERVER_ACCEPTED';
}

class LocalAttendanceDatabase {
  LocalAttendanceDatabase(this._db);

  final Database _db;

  static Future<LocalAttendanceDatabase> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    final dbPath = p.join(directory.path, 'kiit_attendance_goal02.sqlite');
    return LocalAttendanceDatabase(sqlite3.open(dbPath))..migrate();
  }

  factory LocalAttendanceDatabase.inMemory() {
    return LocalAttendanceDatabase(sqlite3.openInMemory())..migrate();
  }

  factory LocalAttendanceDatabase.openAtPath(String path) {
    return LocalAttendanceDatabase(sqlite3.open(path))..migrate();
  }

  void close() => _db.dispose();

  void migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA busy_timeout = 5000;');
    _db.execute('PRAGMA synchronous = FULL;');
    _db.execute('PRAGMA secure_delete = ON;');
    _db.execute('PRAGMA journal_mode = WAL;');
    final currentVersion = _db.userVersion;
    if (currentVersion > localSchemaVersion) {
      throw StateError('local database schema is newer than this app');
    }
    if (currentVersion < 1) {
      _applyMigration(1, _applySchemaV1);
    }
    if (_db.userVersion < 2) {
      _applyMigration(2, _applySchemaV2);
    }
    if (_db.userVersion < 3) {
      _applyMigration(3, _applySchemaV3);
    }
    if (_db.userVersion < 4) {
      _applyMigration(4, _applySchemaV4);
    }
    if (_db.userVersion < 5) {
      _applyMigration(5, _applySchemaV5);
    }
    if (_db.userVersion < 6) {
      _applyMigration(6, _applySchemaV6);
    }
    _recoverInterruptedProofSyncs();
  }

  void _applyMigration(int version, void Function() apply) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      apply();
      _db.userVersion = version;
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _recoverInterruptedProofSyncs() {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''
      UPDATE attendance_proof_outbox
      SET state = 'RETRY_PENDING', next_attempt_at = ?, updated_at = ?,
          last_error_code = 'INTERRUPTED_SYNC'
      WHERE state = 'SYNCING'
      ''',
      [now, now],
    );
    _db.execute(
      '''
      UPDATE attendance_proofs_local
      SET technical_state = 'RETRY_PENDING', updated_at = ?
      WHERE technical_state = 'SYNCING'
      ''',
      [now],
    );
  }

  void applyBootstrap(BootstrapSyncPayload payload) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _replaceAuthorizedProjection(payload.student.id);
      _upsertStudent(payload.student);
      for (final term in payload.academicTerms) {
        _db.execute(
          'INSERT OR REPLACE INTO academic_terms VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            term.id,
            term.name,
            term.academicYear,
            term.termNumber,
            term.startsOn,
            term.endsOn,
            term.status,
          ],
        );
      }
      for (final section in payload.sections) {
        _db.execute(
          'INSERT OR REPLACE INTO sections VALUES (?, ?, ?)',
          [section.id, section.academicTermId, section.code],
        );
      }
      for (final course in payload.courses) {
        _db.execute(
          'INSERT OR REPLACE INTO courses VALUES (?, ?, ?)',
          [course.id, course.code, course.name],
        );
      }
      for (final offering in payload.courseOfferings) {
        _db.execute(
          'INSERT OR REPLACE INTO course_offerings VALUES (?, ?, ?, ?)',
          [
            offering.id,
            offering.courseId,
            offering.academicTermId,
            offering.sectionId,
          ],
        );
      }
      for (final enrollment in payload.enrollments) {
        _db.execute(
          'INSERT OR REPLACE INTO enrollments VALUES (?, ?, ?)',
          [
            enrollment.id,
            enrollment.studentId,
            enrollment.courseOfferingId,
          ],
        );
      }
      for (final faculty in payload.faculty) {
        _db.execute(
          'INSERT OR REPLACE INTO faculty VALUES (?, ?, ?, ?)',
          [
            faculty.id,
            faculty.employeeCode,
            faculty.institutionalEmail,
            faculty.displayName,
          ],
        );
      }
      for (final assignment in payload.facultyAssignments) {
        _db.execute(
          'INSERT OR REPLACE INTO faculty_assignments VALUES (?, ?, ?, ?)',
          [
            assignment.id,
            assignment.facultyId,
            assignment.courseOfferingId,
            assignment.role,
          ],
        );
      }
      for (final entry in payload.timetableEntries) {
        _db.execute(
          'INSERT OR REPLACE INTO timetable_entries VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            entry.id,
            entry.courseOfferingId,
            entry.dayOfWeek,
            entry.startTime,
            entry.endTime,
            entry.room,
            entry.validFrom,
            entry.validUntil,
          ],
        );
      }
      for (final session in payload.attendanceSessions) {
        _db.execute(
          'INSERT OR REPLACE INTO attendance_sessions VALUES (?, ?, ?, ?, ?)',
          [
            session.id,
            session.courseOfferingId,
            session.scheduledStart,
            session.scheduledEnd,
            session.state,
          ],
        );
      }
      for (final record in payload.attendanceRecords) {
        _db.execute(
          'INSERT OR REPLACE INTO attendance_records VALUES (?, ?, ?, ?, ?, ?)',
          [
            record.id,
            record.attendanceSessionId,
            record.studentId,
            record.status,
            record.method,
            record.recordedAt,
          ],
        );
      }
      _db.execute(
        'INSERT OR REPLACE INTO sync_metadata VALUES (?, ?, ?)',
        ['bootstrap', payload.cursor, payload.serverTime],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _replaceAuthorizedProjection(String studentId) {
    final rows = _db.select(
      'SELECT id FROM students WHERE id != ? LIMIT 1',
      [studentId],
    );
    if (rows.isEmpty) return;
    final pendingProofs = _db.select(
      '''
      SELECT 1 FROM attendance_proof_outbox
      WHERE state IN ('QUEUED', 'SYNCING', 'RETRY_PENDING')
      LIMIT 1
      ''',
    );
    if (pendingProofs.isNotEmpty) {
      throw StateError(
        'A different student cannot replace this local account while attendance proofs are awaiting sync.',
      );
    }
    _db.execute('DELETE FROM attendance_proof_outbox');
    _db.execute('DELETE FROM attendance_proofs_local');
    _db.execute('DELETE FROM attendance_claims');
    _db.execute('DELETE FROM attendance_records');
    _db.execute('DELETE FROM attendance_sessions');
    _db.execute('DELETE FROM timetable_entries');
    _db.execute('DELETE FROM faculty_assignments');
    _db.execute('DELETE FROM faculty');
    _db.execute('DELETE FROM enrollments');
    _db.execute('DELETE FROM course_offerings');
    _db.execute('DELETE FROM courses');
    _db.execute('DELETE FROM sections');
    _db.execute('DELETE FROM academic_terms');
    _db.execute('DELETE FROM device_registration_projection');
    _db.execute('DELETE FROM students');
    _db.execute('DELETE FROM sync_metadata');
  }

  void clearLocalAccount() {
    _replaceAuthorizedProjection('__signed_out__');
  }

  StudentProfile? getCurrentStudent() {
    final rows = _db.select('''
      SELECT s.id, s.roll_number, s.display_name, sec.code AS section_code
      FROM students s
      JOIN enrollments e ON e.student_id = s.id
      JOIN course_offerings co ON co.id = e.course_offering_id
      JOIN sections sec ON sec.id = co.section_id
      ORDER BY s.roll_number
      LIMIT 1
    ''');
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return StudentProfile(
      id: row['id'] as String,
      rollNumber: row['roll_number'] as String,
      displayName: row['display_name'] as String,
      sectionCode: row['section_code'] as String,
    );
  }

  List<CourseSummary> getCourseSummaries() {
    final rows = _db.select('''
      SELECT c.code AS course_code,
             c.name AS course_name,
             COUNT(ar.id) AS total_classes,
             SUM(CASE WHEN ar.status = 'PRESENT' THEN 1 ELSE 0 END) AS present,
             SUM(CASE WHEN ar.status = 'ABSENT' THEN 1 ELSE 0 END) AS absent
      FROM courses c
      JOIN course_offerings co ON co.course_id = c.id
      JOIN attendance_sessions sess ON sess.course_offering_id = co.id
      JOIN attendance_records ar ON ar.attendance_session_id = sess.id
      GROUP BY c.id, c.code, c.name
      ORDER BY c.code
    ''');
    return rows.map((row) {
      final present = row['present'] as int;
      final absent = row['absent'] as int;
      return CourseSummary(
        courseCode: row['course_code'] as String,
        courseName: row['course_name'] as String,
        totalClasses: row['total_classes'] as int,
        present: present,
        absent: absent,
        percentage: attendancePercentage(present: present, absent: absent),
      );
    }).toList();
  }

  List<AttendanceHistoryItem> getAttendanceHistory() {
    final rows = _db.select('''
      SELECT c.code AS course_code,
             sess.scheduled_start,
             ar.status,
             ar.method
      FROM attendance_records ar
      JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
      JOIN course_offerings co ON co.id = sess.course_offering_id
      JOIN courses c ON c.id = co.course_id
      ORDER BY sess.scheduled_start DESC
    ''');
    return rows.map((row) {
      return AttendanceHistoryItem(
        courseCode: row['course_code'] as String,
        scheduledStart: row['scheduled_start'] as String,
        status: row['status'] as String,
        method: row['method'] as String?,
      );
    }).toList();
  }

  CourseAttendanceDetail? getCourseAttendanceDetail(String courseCode) {
    final summaries = getCourseSummaries()
        .where((summary) => summary.courseCode == courseCode)
        .toList();
    if (summaries.isEmpty) {
      return null;
    }
    final summary = summaries.first;
    final rows = _db.select(
      '''
      SELECT c.code AS course_code,
             sess.scheduled_start,
             ar.status,
             ar.method
      FROM attendance_records ar
      JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
      JOIN course_offerings co ON co.id = sess.course_offering_id
      JOIN courses c ON c.id = co.course_id
      WHERE c.code = ?
      ORDER BY sess.scheduled_start DESC
      ''',
      [courseCode],
    );
    return CourseAttendanceDetail(
      courseCode: summary.courseCode,
      courseName: summary.courseName,
      present: summary.present,
      absent: summary.absent,
      percentage: summary.percentage,
      history: rows
          .map(
            (row) => AttendanceHistoryItem(
              courseCode: row['course_code'] as String,
              scheduledStart: row['scheduled_start'] as String,
              status: row['status'] as String,
              method: row['method'] as String?,
            ),
          )
          .toList(),
    );
  }

  List<TimetableItem> getTimetableForDay(int dayOfWeek) {
    final rows = _db.select(
      '''
      SELECT c.code AS course_code, c.name AS course_name, sec.code AS section_code,
             te.day_of_week, te.start_time, te.end_time, te.room
      FROM timetable_entries te
      JOIN course_offerings co ON co.id = te.course_offering_id
      JOIN courses c ON c.id = co.course_id
      JOIN sections sec ON sec.id = co.section_id
      WHERE te.day_of_week = ?
      ORDER BY te.start_time, c.code
      ''',
      [dayOfWeek],
    );
    return rows
        .map(
          (row) => TimetableItem(
            courseCode: row['course_code'] as String,
            courseName: row['course_name'] as String,
            sectionCode: row['section_code'] as String,
            dayOfWeek: row['day_of_week'] as int,
            startTime: row['start_time'] as String,
            endTime: row['end_time'] as String,
            room: row['room'] as String,
          ),
        )
        .toList();
  }

  List<AttendanceLogEntry> getRecentAttendanceLog({int limit = 8}) {
    final rows = _db.select(
      '''
      SELECT apl.proof_id,
             apl.session_id,
             c.code AS course_code,
             c.name AS course_name,
             sec.code AS section_code,
             COALESCE(ar.recorded_at, apl.created_at) AS recorded_at,
             ac.claim_state,
             COALESCE(apo.state, apl.technical_state) AS sync_state,
             COALESCE(apo.attempt_count, 0) AS attempt_count,
             apo.last_error_code
      FROM attendance_proofs_local apl
      LEFT JOIN attendance_claims ac ON ac.claim_id = apl.claim_id
      LEFT JOIN attendance_proof_outbox apo ON apo.proof_id = apl.proof_id
      LEFT JOIN attendance_sessions sess ON sess.id = apl.session_id
      LEFT JOIN course_offerings co ON co.id = sess.course_offering_id
      LEFT JOIN courses c ON c.id = co.course_id
      LEFT JOIN sections sec ON sec.id = co.section_id
      LEFT JOIN attendance_records ar
        ON ar.attendance_session_id = apl.session_id
       AND ar.student_id = apl.student_id
      ORDER BY COALESCE(ar.recorded_at, apl.created_at) DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows
        .map(
          (row) => AttendanceLogEntry(
            proofId: row['proof_id'] as String,
            sessionId: row['session_id'] as String,
            courseCode: row['course_code'] as String? ?? 'Course',
            courseName: row['course_name'] as String? ?? 'Attendance session',
            sectionCode: row['section_code'] as String? ?? 'Section',
            recordedAt: row['recorded_at'] as String,
            claimState: row['claim_state'] as String? ?? 'PROOF_READY',
            syncState: row['sync_state'] as String? ?? 'LOCAL_CAPTURED',
            attemptCount: row['attempt_count'] as int? ?? 0,
            lastErrorCode: row['last_error_code'] as String?,
          ),
        )
        .toList();
  }

  bool hasEnrollmentForOffering(String courseOfferingId) {
    final rows = _db.select(
      '''
      SELECT 1 FROM enrollments
      WHERE course_offering_id = ?
      LIMIT 1
      ''',
      [courseOfferingId],
    );
    return rows.isNotEmpty;
  }

  CourseOfferingProjection? getCourseOfferingProjection(
      String courseOfferingId) {
    final rows = _db.select(
      '''
      SELECT co.id AS course_offering_id,
             c.code AS course_code,
             c.name AS course_name,
             sec.code AS section_code
      FROM course_offerings co
      JOIN courses c ON c.id = co.course_id
      JOIN sections sec ON sec.id = co.section_id
      WHERE co.id = ?
      LIMIT 1
      ''',
      [courseOfferingId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CourseOfferingProjection(
      courseOfferingId: row['course_offering_id'] as String,
      courseCode: row['course_code'] as String,
      courseName: row['course_name'] as String,
      sectionCode: row['section_code'] as String,
    );
  }

  void saveLocalSecureProofAttendance({
    required String attendanceRecordId,
    required String sessionId,
    required String courseOfferingId,
    required String studentId,
    required String scheduledStart,
    required String scheduledEnd,
    required String recordedAt,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        INSERT INTO attendance_sessions (
          id, course_offering_id, scheduled_start, scheduled_end, state
        )
        VALUES (?, ?, ?, ?, 'ACTIVE')
        ON CONFLICT (id)
        DO UPDATE SET course_offering_id = excluded.course_offering_id,
                      scheduled_start = excluded.scheduled_start,
                      scheduled_end = excluded.scheduled_end
        ''',
        [sessionId, courseOfferingId, scheduledStart, scheduledEnd],
      );
      _db.execute(
        '''
        INSERT OR REPLACE INTO attendance_records (
          id, attendance_session_id, student_id, status, method, recorded_at
        )
        VALUES (?, ?, ?, 'PRESENT', 'SECURE_PROOF', ?)
        ''',
        [attendanceRecordId, sessionId, studentId, recordedAt],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  AttendanceForecast getOverallForecast({double thresholdPercent = 75}) {
    final rows = _db.select('''
      SELECT SUM(CASE WHEN status = 'PRESENT' THEN 1 ELSE 0 END) AS present,
             SUM(CASE WHEN status = 'ABSENT' THEN 1 ELSE 0 END) AS absent
      FROM attendance_records
    ''');
    final row = rows.first;
    return forecastAttendance(
      present: (row['present'] as int?) ?? 0,
      absent: (row['absent'] as int?) ?? 0,
      thresholdPercent: thresholdPercent,
    );
  }

  void saveDeviceProjection(DeviceRegistrationProjection projection) {
    _db.execute(
      '''
      INSERT OR REPLACE INTO device_registration_projection (
        device_registration_id,
        student_id,
        status,
        key_fingerprint,
        platform,
        display_label,
        last_verified_at,
        server_version
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        projection.deviceRegistrationId,
        projection.studentId,
        projection.status,
        projection.keyFingerprint,
        projection.platform,
        projection.displayLabel,
        projection.lastVerifiedAt,
        projection.serverVersion,
      ],
    );
  }

  DeviceRegistrationProjection? getDeviceProjection() {
    final rows = _db.select('''
      SELECT device_registration_id, student_id, status, key_fingerprint,
             platform, display_label, last_verified_at, server_version
      FROM device_registration_projection
      LIMIT 1
    ''');
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return DeviceRegistrationProjection(
      deviceRegistrationId: row['device_registration_id'] as String,
      studentId: row['student_id'] as String,
      status: row['status'] as String,
      keyFingerprint: row['key_fingerprint'] as String,
      platform: row['platform'] as String,
      displayLabel: row['display_label'] as String?,
      lastVerifiedAt: row['last_verified_at'] as String?,
      serverVersion: row['server_version'] as int,
    );
  }

  void clearDeviceProjection() {
    _db.execute('DELETE FROM device_registration_projection');
  }

  void saveAttendanceClaim(AttendanceClaimProjection claim) {
    _db.execute(
      '''
      INSERT INTO attendance_claims (
        claim_id, session_id, student_id, device_registration_id, qr_epoch,
        qr_challenge, qr_issued_at, qr_expires_at, qr_signature,
        qr_captured_at, claim_created_at, claim_expires_at, claim_state,
        device_signature
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (session_id, student_id)
      DO UPDATE SET claim_state = excluded.claim_state
      ''',
      [
        claim.claimId,
        claim.sessionId,
        claim.studentId,
        claim.deviceRegistrationId,
        claim.qrEpoch,
        claim.qrChallenge,
        claim.qrIssuedAt,
        claim.qrExpiresAt,
        claim.qrSignature,
        claim.qrCapturedAt,
        claim.claimCreatedAt,
        claim.claimExpiresAt,
        claim.claimState,
        claim.deviceSignature,
      ],
    );
  }

  AttendanceClaimProjection? getClaimForSession(
      String sessionId, String studentId) {
    final rows = _db.select(
      '''
      SELECT claim_id, session_id, student_id, device_registration_id, qr_epoch,
             qr_challenge, qr_issued_at, qr_expires_at, qr_signature,
             qr_captured_at, claim_created_at, claim_expires_at, claim_state,
             device_signature
      FROM attendance_claims
      WHERE session_id = ? AND student_id = ?
      LIMIT 1
      ''',
      [sessionId, studentId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return AttendanceClaimProjection(
      claimId: row['claim_id'] as String,
      sessionId: row['session_id'] as String,
      studentId: row['student_id'] as String,
      deviceRegistrationId: row['device_registration_id'] as String,
      qrEpoch: row['qr_epoch'] as int,
      qrChallenge: row['qr_challenge'] as String,
      qrIssuedAt: row['qr_issued_at'] as String,
      qrExpiresAt: row['qr_expires_at'] as String,
      qrSignature: row['qr_signature'] as String,
      qrCapturedAt: row['qr_captured_at'] as String,
      claimCreatedAt: row['claim_created_at'] as String,
      claimExpiresAt: row['claim_expires_at'] as String,
      claimState: row['claim_state'] as String,
      deviceSignature: row['device_signature'] as String,
    );
  }

  void saveProofAndEnqueueOutbox({
    required String proofId,
    required String claimId,
    required String sessionId,
    required String studentId,
    required String deviceRegistrationId,
    required String payloadJson,
    required String createdAt,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        INSERT INTO attendance_proofs_local (
          proof_id, claim_id, session_id, student_id, device_registration_id,
          payload_json, technical_state, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, 'LOCAL_CAPTURED', ?, ?)
        ON CONFLICT (proof_id)
        DO UPDATE SET payload_json = excluded.payload_json,
                      updated_at = excluded.updated_at
        ''',
        [
          proofId,
          claimId,
          sessionId,
          studentId,
          deviceRegistrationId,
          payloadJson,
          createdAt,
          createdAt,
        ],
      );
      _db.execute(
        '''
        INSERT INTO attendance_proof_outbox (
          id, proof_id, session_id, student_id, device_registration_id,
          payload_json, state, attempt_count, next_attempt_at, last_attempt_at,
          created_at, updated_at, last_error_code
        )
        VALUES (?, ?, ?, ?, ?, ?, 'QUEUED', 0, ?, NULL, ?, ?, NULL)
        ON CONFLICT (proof_id)
        DO UPDATE SET payload_json = excluded.payload_json,
                      state = CASE
                        WHEN attendance_proof_outbox.state = 'SERVER_ACCEPTED'
                        THEN attendance_proof_outbox.state
                        ELSE 'QUEUED'
                      END,
                      updated_at = excluded.updated_at
        ''',
        [
          proofId,
          proofId,
          sessionId,
          studentId,
          deviceRegistrationId,
          payloadJson,
          createdAt,
          createdAt,
          createdAt,
        ],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<AttendanceProofOutboxEntry> pendingProofOutboxEntries({
    int limit = 20,
    required String now,
    bool force = false,
  }) {
    final rows = _db.select(
      '''
      SELECT id, proof_id, session_id, student_id, device_registration_id,
             payload_json, state, attempt_count, next_attempt_at,
             last_attempt_at, created_at, updated_at, last_error_code
      FROM attendance_proof_outbox
      WHERE state IN ('QUEUED', 'RETRY_PENDING')
        AND (? = 1 OR next_attempt_at IS NULL OR next_attempt_at <= ?)
      ORDER BY created_at
      LIMIT ?
      ''',
      [force ? 1 : 0, now, limit],
    );
    return rows.map(_outboxEntryFromRow).toList();
  }

  List<AttendanceProofOutboxEntry> rejectedInvalidSignatureOutboxEntries({
    int limit = 10,
  }) {
    final rows = _db.select(
      '''
      SELECT id, proof_id, session_id, student_id, device_registration_id,
             payload_json, state, attempt_count, next_attempt_at,
             last_attempt_at, created_at, updated_at, last_error_code
      FROM attendance_proof_outbox
      WHERE state = 'SERVER_REJECTED'
        AND last_error_code = 'INVALID_SIGNATURE'
      ORDER BY updated_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(_outboxEntryFromRow).toList();
  }

  List<AttendanceProofOutboxEntry> repairableRejectedOutboxEntries({
    int limit = 10,
  }) {
    final rows = _db.select(
      '''
      SELECT id, proof_id, session_id, student_id, device_registration_id,
             payload_json, state, attempt_count, next_attempt_at,
             last_attempt_at, created_at, updated_at, last_error_code
      FROM attendance_proof_outbox
      WHERE state = 'SERVER_REJECTED'
        AND last_error_code IN ('INVALID_SIGNATURE', 'DEVICE_REVOKED')
      ORDER BY updated_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(_outboxEntryFromRow).toList();
  }

  void updateProofPayloadAndRequeue({
    required String proofId,
    required String payloadJson,
    required String now,
    String? claimId,
    String? deviceRegistrationId,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        UPDATE attendance_proofs_local
        SET payload_json = ?,
            device_registration_id = COALESCE(?, device_registration_id),
            technical_state = 'QUEUED',
            updated_at = ?
        WHERE proof_id = ?
        ''',
        [payloadJson, deviceRegistrationId, now, proofId],
      );
      _db.execute(
        '''
        UPDATE attendance_proof_outbox
        SET payload_json = ?,
            device_registration_id = COALESCE(?, device_registration_id),
            state = 'QUEUED',
            next_attempt_at = ?,
            last_error_code = NULL,
            updated_at = ?
        WHERE proof_id = ?
        ''',
        [payloadJson, deviceRegistrationId, now, now, proofId],
      );
      if (claimId != null && deviceRegistrationId != null) {
        _db.execute(
          '''
          UPDATE attendance_claims
          SET device_registration_id = ?
          WHERE claim_id = ?
          ''',
          [deviceRegistrationId, claimId],
        );
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void markProofSyncing(String proofId, String now) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        UPDATE attendance_proofs_local
        SET technical_state = 'SYNCING', updated_at = ?
        WHERE proof_id = ?
        ''',
        [now, proofId],
      );
      _db.execute(
        '''
      UPDATE attendance_proof_outbox
      SET state = 'SYNCING', attempt_count = attempt_count + 1,
          last_attempt_at = ?, updated_at = ?
      WHERE proof_id = ? AND state IN ('QUEUED', 'RETRY_PENDING')
      ''',
        [now, now, proofId],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void markProofAccepted({
    required String proofId,
    required String attendanceRecordId,
    required String sessionId,
    required String studentId,
    required String deviceRegistrationId,
    required String method,
    required String recordedAt,
    required String now,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        INSERT OR REPLACE INTO attendance_records (
          id, attendance_session_id, student_id, status, method, recorded_at
        )
        VALUES (?, ?, ?, 'PRESENT', ?, ?)
        ''',
        [attendanceRecordId, sessionId, studentId, method, recordedAt],
      );
      _db.execute(
        '''
        UPDATE attendance_proofs_local
        SET technical_state = 'SERVER_ACCEPTED', updated_at = ?
        WHERE proof_id = ?
        ''',
        [now, proofId],
      );
      _db.execute(
        '''
        UPDATE attendance_proof_outbox
        SET state = 'SERVER_ACCEPTED', updated_at = ?, last_error_code = NULL
        WHERE proof_id = ?
        ''',
        [now, proofId],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void markProofRetryPending({
    required String proofId,
    required String nextAttemptAt,
    required String now,
    required String errorCode,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        UPDATE attendance_proofs_local
        SET technical_state = 'RETRY_PENDING', updated_at = ?
        WHERE proof_id = ?
        ''',
        [now, proofId],
      );
      _db.execute(
        '''
      UPDATE attendance_proof_outbox
      SET state = 'RETRY_PENDING', next_attempt_at = ?, updated_at = ?,
          last_error_code = ?
      WHERE proof_id = ?
      ''',
        [nextAttemptAt, now, errorCode, proofId],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void markProofRejected({
    required String proofId,
    required String now,
    required String errorCode,
  }) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        '''
        UPDATE attendance_proofs_local
        SET technical_state = 'SERVER_REJECTED', updated_at = ?
        WHERE proof_id = ?
        ''',
        [now, proofId],
      );
      _db.execute(
        '''
      UPDATE attendance_proof_outbox
      SET state = 'SERVER_REJECTED', updated_at = ?, last_error_code = ?
      WHERE proof_id = ?
      ''',
        [now, errorCode, proofId],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  AttendanceProofOutboxEntry _outboxEntryFromRow(Row row) {
    return AttendanceProofOutboxEntry(
      id: row['id'] as String,
      proofId: row['proof_id'] as String,
      sessionId: row['session_id'] as String,
      studentId: row['student_id'] as String,
      deviceRegistrationId: row['device_registration_id'] as String,
      payloadJson: row['payload_json'] as String,
      state: row['state'] as String,
      attemptCount: row['attempt_count'] as int,
      nextAttemptAt: row['next_attempt_at'] as String?,
      lastAttemptAt: row['last_attempt_at'] as String?,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
      lastErrorCode: row['last_error_code'] as String?,
    );
  }

  void _upsertStudent(StudentDto student) {
    _db.execute(
      'INSERT OR REPLACE INTO students VALUES (?, ?, ?, ?)',
      [
        student.id,
        student.rollNumber,
        student.institutionalEmail,
        student.displayName,
      ],
    );
  }

  void _applySchemaV1() {
    _db.execute('''
      CREATE TABLE students (
        id TEXT PRIMARY KEY,
        roll_number TEXT NOT NULL UNIQUE,
        institutional_email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL
      );

      CREATE TABLE academic_terms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        academic_year TEXT NOT NULL,
        term_number INTEGER NOT NULL,
        starts_on TEXT NOT NULL,
        ends_on TEXT NOT NULL,
        status TEXT NOT NULL
      );

      CREATE TABLE sections (
        id TEXT PRIMARY KEY,
        academic_term_id TEXT NOT NULL,
        code TEXT NOT NULL,
        FOREIGN KEY (academic_term_id) REFERENCES academic_terms(id)
      );

      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL
      );

      CREATE TABLE course_offerings (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        academic_term_id TEXT NOT NULL,
        section_id TEXT NOT NULL,
        FOREIGN KEY (course_id) REFERENCES courses(id),
        FOREIGN KEY (academic_term_id) REFERENCES academic_terms(id),
        FOREIGN KEY (section_id) REFERENCES sections(id)
      );

      CREATE TABLE enrollments (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        course_offering_id TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id),
        FOREIGN KEY (course_offering_id) REFERENCES course_offerings(id)
      );

      CREATE TABLE faculty (
        id TEXT PRIMARY KEY,
        employee_code TEXT,
        institutional_email TEXT NOT NULL,
        display_name TEXT NOT NULL
      );

      CREATE TABLE faculty_assignments (
        id TEXT PRIMARY KEY,
        faculty_id TEXT NOT NULL,
        course_offering_id TEXT NOT NULL,
        role TEXT NOT NULL,
        FOREIGN KEY (faculty_id) REFERENCES faculty(id),
        FOREIGN KEY (course_offering_id) REFERENCES course_offerings(id)
      );

      CREATE TABLE attendance_sessions (
        id TEXT PRIMARY KEY,
        course_offering_id TEXT NOT NULL,
        scheduled_start TEXT NOT NULL,
        scheduled_end TEXT NOT NULL,
        state TEXT NOT NULL,
        FOREIGN KEY (course_offering_id) REFERENCES course_offerings(id)
      );

      CREATE TABLE attendance_records (
        id TEXT PRIMARY KEY,
        attendance_session_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('PRESENT', 'ABSENT')),
        method TEXT CHECK (
          method IN ('DYNAMIC_QR', 'FACULTY_ATTESTATION', 'SECURE_PROOF')
        ),
        recorded_at TEXT NOT NULL,
        UNIQUE (attendance_session_id, student_id),
        CHECK (
          (status = 'PRESENT' AND method IS NOT NULL)
          OR (status = 'ABSENT' AND method IS NULL)
        ),
        FOREIGN KEY (attendance_session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      CREATE TABLE sync_metadata (
        scope TEXT PRIMARY KEY,
        cursor TEXT NOT NULL,
        server_time TEXT NOT NULL
      );

      CREATE INDEX idx_local_enrollments_student ON enrollments(student_id);
      CREATE INDEX idx_local_attendance_records_student
        ON attendance_records(student_id);
      CREATE INDEX idx_local_sessions_offering
        ON attendance_sessions(course_offering_id);
    ''');
  }

  void _applySchemaV2() {
    _db.execute('''
      CREATE TABLE device_registration_projection (
        device_registration_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('PENDING', 'ACTIVE', 'REVOKED')),
        key_fingerprint TEXT NOT NULL,
        platform TEXT NOT NULL,
        display_label TEXT,
        last_verified_at TEXT,
        server_version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      CREATE INDEX idx_local_device_projection_student
        ON device_registration_projection(student_id);
    ''');
  }

  void _applySchemaV3() {
    _db.execute('''
      CREATE TABLE timetable_entries (
        id TEXT PRIMARY KEY,
        course_offering_id TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        room TEXT NOT NULL,
        valid_from TEXT NOT NULL,
        valid_until TEXT NOT NULL,
        FOREIGN KEY (course_offering_id) REFERENCES course_offerings(id)
      );

      CREATE TABLE attendance_claims (
        claim_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        device_registration_id TEXT NOT NULL,
        qr_epoch INTEGER NOT NULL,
        qr_challenge TEXT NOT NULL,
        qr_captured_at TEXT NOT NULL,
        claim_created_at TEXT NOT NULL,
        claim_expires_at TEXT NOT NULL,
        claim_state TEXT NOT NULL CHECK (
          claim_state IN (
            'CAPTURED',
            'AWAITING_PRESENCE',
            'PROOF_READY',
            'EXPIRED',
            'REJECTED',
            'CONSUMED'
          )
        ),
        device_signature TEXT NOT NULL,
        UNIQUE (session_id, student_id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      CREATE INDEX idx_local_timetable_day ON timetable_entries(day_of_week);
      CREATE INDEX idx_local_claims_session_student
        ON attendance_claims(session_id, student_id);
    ''');
  }

  void _applySchemaV4() {
    _db.execute('''
      CREATE TABLE attendance_records_v4 (
        id TEXT PRIMARY KEY,
        attendance_session_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('PRESENT', 'ABSENT')),
        method TEXT CHECK (
          method IN ('DYNAMIC_QR', 'FACULTY_ATTESTATION', 'SECURE_PROOF')
        ),
        recorded_at TEXT NOT NULL,
        UNIQUE (attendance_session_id, student_id),
        CHECK (
          (status = 'PRESENT' AND method IS NOT NULL)
          OR (status = 'ABSENT' AND method IS NULL)
        ),
        FOREIGN KEY (attendance_session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      INSERT INTO attendance_records_v4 (
        id, attendance_session_id, student_id, status, method, recorded_at
      )
      SELECT id, attendance_session_id, student_id, status, method, recorded_at
      FROM attendance_records;

      DROP TABLE attendance_records;
      ALTER TABLE attendance_records_v4 RENAME TO attendance_records;

      CREATE INDEX idx_local_attendance_records_student
        ON attendance_records(student_id);

      CREATE TABLE attendance_proofs_local (
        proof_id TEXT PRIMARY KEY,
        claim_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        device_registration_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        technical_state TEXT NOT NULL CHECK (
          technical_state IN (
            'LOCAL_CAPTURED',
            'QUEUED',
            'SYNCING',
            'RETRY_PENDING',
            'SERVER_ACCEPTED',
            'SERVER_REJECTED',
            'CONFLICT_REVIEW'
          )
        ),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (claim_id) REFERENCES attendance_claims(claim_id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      CREATE TABLE attendance_proof_outbox (
        id TEXT PRIMARY KEY,
        proof_id TEXT NOT NULL UNIQUE,
        session_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        device_registration_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        state TEXT NOT NULL CHECK (
          state IN (
            'QUEUED',
            'SYNCING',
            'RETRY_PENDING',
            'SERVER_ACCEPTED',
            'SERVER_REJECTED',
            'CONFLICT_REVIEW'
          )
        ),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_attempt_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_error_code TEXT,
        FOREIGN KEY (proof_id) REFERENCES attendance_proofs_local(proof_id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      );

      CREATE INDEX idx_local_proof_outbox_state_next
        ON attendance_proof_outbox(state, next_attempt_at, created_at);
      CREATE INDEX idx_local_proofs_session_student
        ON attendance_proofs_local(session_id, student_id);
    ''');
  }

  void _applySchemaV5() {
    _db.execute('''
      ALTER TABLE attendance_claims ADD COLUMN qr_issued_at TEXT;
      ALTER TABLE attendance_claims ADD COLUMN qr_expires_at TEXT;
      ALTER TABLE attendance_claims ADD COLUMN qr_signature TEXT;
      UPDATE attendance_claims
      SET qr_issued_at = COALESCE(qr_issued_at, qr_captured_at),
          qr_expires_at = COALESCE(qr_expires_at, claim_expires_at),
          qr_signature = COALESCE(qr_signature, 'legacy-unverified');
    ''');
  }

  void _applySchemaV6() {
    // A process can terminate between marking an outbox row SYNCING and
    // receiving the server response. Startup recovery returns it to retry.
    _recoverInterruptedProofSyncs();
  }
}

Future<bool> localDatabaseFileExists() async {
  final directory = await getApplicationSupportDirectory();
  return File(p.join(directory.path, 'kiit_attendance_goal02.sqlite')).exists();
}
