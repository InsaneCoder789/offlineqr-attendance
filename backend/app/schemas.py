from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class StudentOut(BaseModel):
    id: UUID
    roll_number: str
    institutional_email: str
    display_name: str


class DevLoginIn(BaseModel):
    email: str


class StudentLoginIn(BaseModel):
    roll_number: str
    password: str


class StudentLoginOut(StudentOut):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int
    must_change_password: bool


class StudentPasswordChangeIn(BaseModel):
    current_password: str
    new_password: str


class StudentPasswordResetOut(BaseModel):
    temporary_password: str


class AcademicTermOut(BaseModel):
    id: UUID
    name: str
    academic_year: str
    term_number: int
    starts_on: str
    ends_on: str
    status: str


class SectionOut(BaseModel):
    id: UUID
    academic_term_id: UUID
    code: str


class CourseOut(BaseModel):
    id: UUID
    code: str
    name: str


class CourseOfferingOut(BaseModel):
    id: UUID
    course_id: UUID
    academic_term_id: UUID
    section_id: UUID


class EnrollmentOut(BaseModel):
    id: UUID
    student_id: UUID
    course_offering_id: UUID


class FacultyOut(BaseModel):
    id: UUID
    employee_code: str | None
    institutional_email: str
    display_name: str


class FacultyAssignmentOut(BaseModel):
    id: UUID
    faculty_id: UUID
    course_offering_id: UUID
    role: str


class TimetableEntryOut(BaseModel):
    id: UUID
    course_offering_id: UUID
    day_of_week: int
    start_time: str
    end_time: str
    room: str
    valid_from: str
    valid_until: str


class AttendanceSessionOut(BaseModel):
    id: UUID
    course_offering_id: UUID
    scheduled_start: datetime
    scheduled_end: datetime
    state: str


class AttendanceRecordOut(BaseModel):
    id: UUID
    attendance_session_id: UUID
    student_id: UUID
    status: str
    method: str | None
    recorded_at: datetime


class AttendanceSummaryOut(BaseModel):
    course_id: UUID
    course_code: str
    course_name: str
    total_classes: int
    present: int
    absent: int
    percentage: float


class BootstrapSyncOut(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda value: value.isoformat()})

    sync_version: int
    server_time: datetime
    student: StudentOut
    academic_terms: list[AcademicTermOut]
    sections: list[SectionOut]
    courses: list[CourseOut]
    course_offerings: list[CourseOfferingOut]
    enrollments: list[EnrollmentOut]
    faculty: list[FacultyOut]
    faculty_assignments: list[FacultyAssignmentOut]
    timetable_entries: list[TimetableEntryOut] = []
    attendance_sessions: list[AttendanceSessionOut]
    attendance_records: list[AttendanceRecordOut]
    attendance_summaries: list[AttendanceSummaryOut]
    cursor: str
