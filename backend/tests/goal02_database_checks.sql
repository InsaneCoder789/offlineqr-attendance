DO $$
DECLARE
    dev_student uuid := '50000000-0000-4000-8000-000000000001';
    daa_course uuid := '30000000-0000-4000-8000-000000000001';
    daa_total integer;
    daa_present integer;
    leaked_students integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students WHERE roll_number = 'DEV24155001') THEN
        RAISE EXCEPTION 'deterministic development student missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM attendance_records
        WHERE status = 'ABSENT' AND method IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'ABSENT records must not have attendance method';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM attendance_records
        WHERE status = 'PRESENT' AND method IS NULL
    ) THEN
        RAISE EXCEPTION 'PRESENT records must have attendance method';
    END IF;

    SELECT COUNT(*), COUNT(*) FILTER (WHERE ar.status = 'PRESENT')
    INTO daa_total, daa_present
    FROM attendance_records ar
    JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
    WHERE ar.student_id = dev_student
      AND sess.course_offering_id = '60000000-0000-4000-8000-000000000001'
      AND sess.state = 'CLOSED';

    IF daa_total != 3 OR daa_present != 2 THEN
        RAISE EXCEPTION 'unexpected DAA attendance counts: total %, present %', daa_total, daa_present;
    END IF;

    SELECT COUNT(DISTINCT roster.student_id)
    INTO leaked_students
    FROM attendance_session_roster roster
    JOIN attendance_sessions sess ON sess.id = roster.attendance_session_id
    JOIN course_offerings co ON co.id = sess.course_offering_id
    WHERE co.course_id = daa_course;

    IF leaked_students < 8 THEN
        RAISE EXCEPTION 'expected roster snapshot does not include seeded section students';
    END IF;
END $$;

-- Non-negotiable uniqueness: same session/student cannot be inserted twice.
DO $$
BEGIN
    INSERT INTO attendance_records (
        attendance_session_id,
        student_id,
        status,
        method,
        recorded_at
    )
    VALUES (
        '80000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000001',
        'PRESENT',
        'DYNAMIC_QR',
        now()
    );
    RAISE EXCEPTION 'duplicate attendance insert unexpectedly succeeded';
EXCEPTION
    WHEN unique_violation THEN
        NULL;
END $$;

