import 'package:client/core/sync/bootstrap_models.dart';

// Keeping nested const constructors makes the fixture easy to copy into
// smaller contract tests without changing allocation semantics.
// ignore_for_file: unnecessary_const

BootstrapSyncPayload sampleBootstrapPayload() {
  return const BootstrapSyncPayload(
    syncVersion: 1,
    serverTime: '2026-08-18T10:00:00Z',
    student: const StudentDto(
      id: '50000000-0000-4000-8000-000000000001',
      rollNumber: 'DEV24155001',
      institutionalEmail: 'dev24155001@example.edu',
      displayName: 'Aarav Mehta',
    ),
    academicTerms: const [
      AcademicTermDto(
        id: '10000000-0000-4000-8000-000000000001',
        name: 'Autumn 2026',
        academicYear: '2026-27',
        termNumber: 1,
        startsOn: '2026-08-01',
        endsOn: '2026-12-20',
        status: 'ACTIVE',
      ),
    ],
    sections: const [
      SectionDto(
        id: '20000000-0000-4000-8000-000000000021',
        academicTermId: '10000000-0000-4000-8000-000000000001',
        code: 'CSE-21',
      ),
    ],
    courses: const [
      CourseDto(
        id: '30000000-0000-4000-8000-000000000001',
        code: 'DAA',
        name: 'Design and Analysis of Algorithms',
      ),
      CourseDto(
        id: '30000000-0000-4000-8000-000000000002',
        code: 'CN',
        name: 'Computer Networks',
      ),
    ],
    courseOfferings: const [
      CourseOfferingDto(
        id: '60000000-0000-4000-8000-000000000001',
        courseId: '30000000-0000-4000-8000-000000000001',
        academicTermId: '10000000-0000-4000-8000-000000000001',
        sectionId: '20000000-0000-4000-8000-000000000021',
      ),
      CourseOfferingDto(
        id: '60000000-0000-4000-8000-000000000002',
        courseId: '30000000-0000-4000-8000-000000000002',
        academicTermId: '10000000-0000-4000-8000-000000000001',
        sectionId: '20000000-0000-4000-8000-000000000021',
      ),
    ],
    enrollments: const [
      EnrollmentDto(
        id: '90000000-0000-4000-8000-000000000001',
        studentId: '50000000-0000-4000-8000-000000000001',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
      ),
      EnrollmentDto(
        id: '90000000-0000-4000-8000-000000000002',
        studentId: '50000000-0000-4000-8000-000000000001',
        courseOfferingId: '60000000-0000-4000-8000-000000000002',
      ),
    ],
    faculty: const [
      FacultyDto(
        id: '40000000-0000-4000-8000-000000000001',
        employeeCode: 'DEVFAC001',
        institutionalEmail: 'ananya.sen@example.edu',
        displayName: 'Dr. Ananya Sen',
      ),
    ],
    facultyAssignments: const [
      FacultyAssignmentDto(
        id: '70000000-0000-4000-8000-000000000001',
        facultyId: '40000000-0000-4000-8000-000000000001',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
        role: 'PRIMARY',
      ),
    ],
    timetableEntries: const [
      TimetableEntryDto(
        id: 'b0000000-0000-4000-8000-000000000001',
        courseOfferingId: '60000000-0000-4000-8000-000000000002',
        dayOfWeek: 2,
        startTime: '09:00:00',
        endTime: '09:50:00',
        room: 'C-304',
        validFrom: '2026-08-01',
        validUntil: '2026-12-20',
      ),
      TimetableEntryDto(
        id: 'b0000000-0000-4000-8000-000000000002',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
        dayOfWeek: 2,
        startTime: '10:00:00',
        endTime: '10:50:00',
        room: 'C-304',
        validFrom: '2026-08-01',
        validUntil: '2026-12-20',
      ),
    ],
    attendanceSessions: const [
      AttendanceSessionDto(
        id: '80000000-0000-4000-8000-000000000001',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
        scheduledStart: '2026-08-10T04:30:00Z',
        scheduledEnd: '2026-08-10T05:30:00Z',
        state: 'CLOSED',
      ),
      AttendanceSessionDto(
        id: '80000000-0000-4000-8000-000000000002',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
        scheduledStart: '2026-08-12T04:30:00Z',
        scheduledEnd: '2026-08-12T05:30:00Z',
        state: 'CLOSED',
      ),
      AttendanceSessionDto(
        id: '80000000-0000-4000-8000-000000000003',
        courseOfferingId: '60000000-0000-4000-8000-000000000001',
        scheduledStart: '2026-08-14T04:30:00Z',
        scheduledEnd: '2026-08-14T05:30:00Z',
        state: 'CLOSED',
      ),
    ],
    attendanceRecords: const [
      AttendanceRecordDto(
        id: 'a0000000-0000-4000-8000-000000000001',
        attendanceSessionId: '80000000-0000-4000-8000-000000000001',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'PRESENT',
        method: 'DYNAMIC_QR',
        recordedAt: '2026-08-10T04:33:00Z',
      ),
      AttendanceRecordDto(
        id: 'a0000000-0000-4000-8000-000000000002',
        attendanceSessionId: '80000000-0000-4000-8000-000000000002',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'PRESENT',
        method: 'FACULTY_ATTESTATION',
        recordedAt: '2026-08-12T04:36:00Z',
      ),
      AttendanceRecordDto(
        id: 'a0000000-0000-4000-8000-000000000003',
        attendanceSessionId: '80000000-0000-4000-8000-000000000003',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'ABSENT',
        method: null,
        recordedAt: '2026-08-14T04:40:00Z',
      ),
    ],
    cursor: 'goal02:fixture:v1',
  );
}
