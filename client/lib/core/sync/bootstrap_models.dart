class BootstrapSyncPayload {
  const BootstrapSyncPayload({
    required this.syncVersion,
    required this.serverTime,
    required this.student,
    required this.academicTerms,
    required this.sections,
    required this.courses,
    required this.courseOfferings,
    required this.enrollments,
    required this.faculty,
    required this.facultyAssignments,
    required this.timetableEntries,
    required this.attendanceSessions,
    required this.attendanceRecords,
    required this.cursor,
  });

  final int syncVersion;
  final String serverTime;
  final StudentDto student;
  final List<AcademicTermDto> academicTerms;
  final List<SectionDto> sections;
  final List<CourseDto> courses;
  final List<CourseOfferingDto> courseOfferings;
  final List<EnrollmentDto> enrollments;
  final List<FacultyDto> faculty;
  final List<FacultyAssignmentDto> facultyAssignments;
  final List<TimetableEntryDto> timetableEntries;
  final List<AttendanceSessionDto> attendanceSessions;
  final List<AttendanceRecordDto> attendanceRecords;
  final String cursor;

  factory BootstrapSyncPayload.fromJson(Map<String, dynamic> json) {
    return BootstrapSyncPayload(
      syncVersion: json['sync_version'] as int,
      serverTime: json['server_time'] as String,
      student: StudentDto.fromJson(json['student'] as Map<String, dynamic>),
      academicTerms: _list(json, 'academic_terms', AcademicTermDto.fromJson),
      sections: _list(json, 'sections', SectionDto.fromJson),
      courses: _list(json, 'courses', CourseDto.fromJson),
      courseOfferings:
          _list(json, 'course_offerings', CourseOfferingDto.fromJson),
      enrollments: _list(json, 'enrollments', EnrollmentDto.fromJson),
      faculty: _list(json, 'faculty', FacultyDto.fromJson),
      facultyAssignments:
          _list(json, 'faculty_assignments', FacultyAssignmentDto.fromJson),
      timetableEntries:
          _list(json, 'timetable_entries', TimetableEntryDto.fromJson),
      attendanceSessions:
          _list(json, 'attendance_sessions', AttendanceSessionDto.fromJson),
      attendanceRecords:
          _list(json, 'attendance_records', AttendanceRecordDto.fromJson),
      cursor: json['cursor'] as String,
    );
  }
}

List<T> _list<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) fromJson,
) {
  return ((json[key] as List<dynamic>?) ?? [])
      .map((value) => fromJson(value as Map<String, dynamic>))
      .toList();
}

class StudentDto {
  const StudentDto({
    required this.id,
    required this.rollNumber,
    required this.institutionalEmail,
    required this.displayName,
  });

  final String id;
  final String rollNumber;
  final String institutionalEmail;
  final String displayName;

  factory StudentDto.fromJson(Map<String, dynamic> json) => StudentDto(
        id: json['id'] as String,
        rollNumber: json['roll_number'] as String,
        institutionalEmail: json['institutional_email'] as String,
        displayName: json['display_name'] as String,
      );
}

class AcademicTermDto {
  const AcademicTermDto({
    required this.id,
    required this.name,
    required this.academicYear,
    required this.termNumber,
    required this.startsOn,
    required this.endsOn,
    required this.status,
  });

  final String id;
  final String name;
  final String academicYear;
  final int termNumber;
  final String startsOn;
  final String endsOn;
  final String status;

  factory AcademicTermDto.fromJson(Map<String, dynamic> json) =>
      AcademicTermDto(
        id: json['id'] as String,
        name: json['name'] as String,
        academicYear: json['academic_year'] as String,
        termNumber: json['term_number'] as int,
        startsOn: json['starts_on'] as String,
        endsOn: json['ends_on'] as String,
        status: json['status'] as String,
      );
}

class SectionDto {
  const SectionDto({
    required this.id,
    required this.academicTermId,
    required this.code,
  });

  final String id;
  final String academicTermId;
  final String code;

  factory SectionDto.fromJson(Map<String, dynamic> json) => SectionDto(
        id: json['id'] as String,
        academicTermId: json['academic_term_id'] as String,
        code: json['code'] as String,
      );
}

class CourseDto {
  const CourseDto({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  factory CourseDto.fromJson(Map<String, dynamic> json) => CourseDto(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
      );
}

class CourseOfferingDto {
  const CourseOfferingDto({
    required this.id,
    required this.courseId,
    required this.academicTermId,
    required this.sectionId,
  });

  final String id;
  final String courseId;
  final String academicTermId;
  final String sectionId;

  factory CourseOfferingDto.fromJson(Map<String, dynamic> json) =>
      CourseOfferingDto(
        id: json['id'] as String,
        courseId: json['course_id'] as String,
        academicTermId: json['academic_term_id'] as String,
        sectionId: json['section_id'] as String,
      );
}

class EnrollmentDto {
  const EnrollmentDto({
    required this.id,
    required this.studentId,
    required this.courseOfferingId,
  });

  final String id;
  final String studentId;
  final String courseOfferingId;

  factory EnrollmentDto.fromJson(Map<String, dynamic> json) => EnrollmentDto(
        id: json['id'] as String,
        studentId: json['student_id'] as String,
        courseOfferingId: json['course_offering_id'] as String,
      );
}

class FacultyDto {
  const FacultyDto({
    required this.id,
    required this.employeeCode,
    required this.institutionalEmail,
    required this.displayName,
  });

  final String id;
  final String? employeeCode;
  final String institutionalEmail;
  final String displayName;

  factory FacultyDto.fromJson(Map<String, dynamic> json) => FacultyDto(
        id: json['id'] as String,
        employeeCode: json['employee_code'] as String?,
        institutionalEmail: json['institutional_email'] as String,
        displayName: json['display_name'] as String,
      );
}

class FacultyAssignmentDto {
  const FacultyAssignmentDto({
    required this.id,
    required this.facultyId,
    required this.courseOfferingId,
    required this.role,
  });

  final String id;
  final String facultyId;
  final String courseOfferingId;
  final String role;

  factory FacultyAssignmentDto.fromJson(Map<String, dynamic> json) =>
      FacultyAssignmentDto(
        id: json['id'] as String,
        facultyId: json['faculty_id'] as String,
        courseOfferingId: json['course_offering_id'] as String,
        role: json['role'] as String,
      );
}

class TimetableEntryDto {
  const TimetableEntryDto({
    required this.id,
    required this.courseOfferingId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.validFrom,
    required this.validUntil,
  });

  final String id;
  final String courseOfferingId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String room;
  final String validFrom;
  final String validUntil;

  factory TimetableEntryDto.fromJson(Map<String, dynamic> json) =>
      TimetableEntryDto(
        id: json['id'] as String,
        courseOfferingId: json['course_offering_id'] as String,
        dayOfWeek: json['day_of_week'] as int,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
        room: json['room'] as String,
        validFrom: json['valid_from'] as String,
        validUntil: json['valid_until'] as String,
      );
}

class AttendanceSessionDto {
  const AttendanceSessionDto({
    required this.id,
    required this.courseOfferingId,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.state,
  });

  final String id;
  final String courseOfferingId;
  final String scheduledStart;
  final String scheduledEnd;
  final String state;

  factory AttendanceSessionDto.fromJson(Map<String, dynamic> json) =>
      AttendanceSessionDto(
        id: json['id'] as String,
        courseOfferingId: json['course_offering_id'] as String,
        scheduledStart: json['scheduled_start'] as String,
        scheduledEnd: json['scheduled_end'] as String,
        state: json['state'] as String,
      );
}

class AttendanceRecordDto {
  const AttendanceRecordDto({
    required this.id,
    required this.attendanceSessionId,
    required this.studentId,
    required this.status,
    required this.method,
    required this.recordedAt,
  });

  final String id;
  final String attendanceSessionId;
  final String studentId;
  final String status;
  final String? method;
  final String recordedAt;

  factory AttendanceRecordDto.fromJson(Map<String, dynamic> json) =>
      AttendanceRecordDto(
        id: json['id'] as String,
        attendanceSessionId: json['attendance_session_id'] as String,
        studentId: json['student_id'] as String,
        status: json['status'] as String,
        method: json['method'] as String?,
        recordedAt: json['recorded_at'] as String,
      );
}
