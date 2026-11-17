-- Cutoff | CP3: application query catalogue
-- Uses the 16 normalized tables created by 03_schema.sql.
-- Each statement has a stable READ/WRITE ID for the CP4 timing table.
--
-- Loading this file PREPAREs statements; it does not execute business writes.
-- In one psql session (prepared statements last only for that session):
--   \i dbms/04_queries.sql
--   EXECUTE cutoff_r3(NULL, NULL, NULL, 20, 0);
--   EXPLAIN (ANALYZE, BUFFERS) EXECUTE cutoff_r3(NULL, NULL, NULL, 20, 0);
-- Run each EXPLAIN three times for CP4. Benchmark writes in BEGIN / ROLLBACK
-- using valid fixture IDs and workflow prerequisites; roll back each run.
-- Reconnect before reloading this file to avoid duplicate PREPARE names.
--
-- HOW TO READ A QUERY
-- PREPARE names a query; the SELECT/INSERT/UPDATE/DELETE below is the query itself.
-- $1 is the first input, $2 is the second, and so on (listed above each query).
-- Example: EXECUTE cutoff_r2(7); reads the profile whose user_id is 7.
-- AS gives a table or result column a readable name.
-- CASE WHEN condition THEN value ELSE other_value END is SQL's if/else.
-- WITH names intermediate results used only within that one query.
--
-- PARAMETERS AND ACCESS
-- $1, $2, ... are bound parameters, never SQL text concatenated from a request.
-- user_id comes from the authenticated backend identity, not a client body.
-- R1 returns a password hash ONLY for backend password verification.
-- R11-R14 reveal evaluation only for submitted attempts owned by that user.
-- R15-R16 and W8-W19 are trusted import operations, not student endpoints.
-- Parameter comments list the order. IDs are BIGINT; marks/answers use NUMERIC.
--
-- STUDENT WORKFLOWS
-- Register: R1 duplicate lookup -> hash password in backend -> W1.
-- Login: R1 -> verify hash in backend; R2 retrieves the public account profile.
-- Browse: R3-R7. R5-R7 deliberately exclude keys and explanations.
-- Start/resume: BEGIN -> W7 closes an expired active attempt -> W2 tries to
-- create one -> R8 returns the active attempt -> COMMIT. W2's conflict handling
-- makes simultaneous start requests return the same active attempt through R8.
-- Save a COMPLETE answer state: BEGIN -> R17 (must return one owned active row)
-- -> W3 (must return one row) -> W4 clears old selections -> W5 inserts the new
-- set for a choice question -> COMMIT. For numerical answers omit W5.
-- Any error, missing authorization row or invalid parameter means ROLLBACK.
-- The deadline is checked when W3 admits the save under the R17 lock. W4/W5
-- finish that admitted save in the same transaction, even at a timer boundary.
-- Empty option array clears a choice answer. NULL numeric input clears a number.
-- Use a validated text[] for option labels, and a non-null review flag.
-- time_spent_seconds is a nonnegative cumulative per-question total, not a delta.
-- Repeated saves therefore do not add the same elapsed time twice.
-- Submit: BEGIN -> R17 -> W6 -> COMMIT, then R11-R13. If already submitted,
-- return existing results; do not reopen the attempt. W7 handles timeout closure.
-- R14 supplies attempt history; R18 is the database health probe.
--
-- IMPORT WORKFLOW
-- BEGIN -> W8-W10 (taxonomy; R15 resolves existing IDs) -> W18 (NEW paper)
-- -> W11-W17 (NEW question content and keys) -> W19 (paper mappings)
-- -> R16 (must return zero issues) -> SET CONSTRAINTS ALL IMMEDIATE -> COMMIT.
-- W19 is used only for the new paper created in this transaction. Reuse existing
-- verified question IDs by mapping them; never update content/keys of a used
-- question or mappings/marks of a used paper. Corrections get new IDs.
-- Import all rows in one transaction so incomplete papers are never visible.
--
-- There are no cached score writes: results are derived from immutable questions,
-- keys, paper-specific marks and saved responses, as specified in CP1.


-- @R1
-- READ R1 | Find an account for login or duplicate-email checking
-- Parameters: $1: email
-- Backend only; never return password_hash in an HTTP response.
PREPARE cutoff_r1(TEXT) AS
SELECT user_id, user_name, email, password_hash
FROM cutoff.users
WHERE email = lower(TRIM($1));


-- @R2
-- READ R2 | Read the signed-in student profile
-- Parameters: $1: authenticated_user_id
PREPARE cutoff_r2(BIGINT) AS
SELECT user_id, user_name, email, user_created_at, user_updated_at
FROM cutoff.users
WHERE user_id = $1;


-- @R3
-- READ R3 | Browse papers with optional filters and pagination
-- Parameters: $1: year or NULL, $2: session or NULL, $3: title search or NULL, $4: limit, $5: offset
PREPARE cutoff_r3(INTEGER, TEXT, TEXT, INTEGER, INTEGER) AS
SELECT paper.test_id, paper.test_title, paper.exam_year, paper.session_label, paper.duration_minutes,
       count(paper_question.question_id) AS question_count,
       sum(paper_question.marks_correct) AS maximum_marks
FROM cutoff.tests AS paper
JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = paper.test_id
WHERE ($1 IS NULL OR paper.exam_year = $1)
  AND ($2 IS NULL OR lower(paper.session_label) = lower($2))
  AND ($3 IS NULL OR paper.test_title ILIKE '%' || $3 || '%')
GROUP BY paper.test_id
ORDER BY paper.exam_year DESC, paper.test_id DESC
LIMIT LEAST(GREATEST(COALESCE($4, 20), 1), 100)
OFFSET GREATEST(COALESCE($5, 0), 0);


-- @R4
-- READ R4 | Read paper details and subject-wise question/mark counts
-- Parameters: $1: test_id
PREPARE cutoff_r4(BIGINT) AS
SELECT paper.test_id, paper.test_title, paper.exam_year, paper.session_label, paper.duration_minutes,
       subject.subject_id, subject.subject_name,
       count(paper_question.question_id) AS question_count,
       coalesce(sum(paper_question.marks_correct), 0) AS maximum_marks
FROM cutoff.tests AS paper
LEFT JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = paper.test_id
LEFT JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
LEFT JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
LEFT JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
WHERE paper.test_id = $1
GROUP BY paper.test_id, subject.subject_id, subject.subject_name
ORDER BY subject.subject_name NULLS LAST;


-- @R5
-- READ R5 | Deliver paper questions without answers or explanations
-- Parameters: $1: test_id
PREPARE cutoff_r5(BIGINT) AS
SELECT paper_question.position, question.question_id, question.question_text, question.question_type, question.difficulty,
       subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
       topic.topic_id, topic.topic_name,
       paper_question.marks_correct, paper_question.marks_incorrect, paper_question.marks_unattempted
FROM cutoff.test_questions AS paper_question
JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
LEFT JOIN cutoff.question_topics AS question_topic ON question_topic.question_id = question.question_id
LEFT JOIN cutoff.topics AS topic ON topic.topic_id = question_topic.topic_id
WHERE paper_question.test_id = $1
ORDER BY paper_question.position;


-- @R6
-- READ R6 | Deliver choice options and their ordered images
-- Parameters: $1: test_id
-- Collect each option's images into one JSON list, so an option appears only once.
-- FILTER ignores the empty image row produced by LEFT JOIN; COALESCE returns [].
PREPARE cutoff_r6(BIGINT) AS
SELECT paper_question.question_id, option.option_label, option.option_text,
       coalesce(jsonb_agg(jsonb_build_object(
           'position', option_image.image_position, 'url', option_image.image_url
       ) ORDER BY option_image.image_position) FILTER (WHERE option_image.image_position IS NOT NULL),
       '[]'::JSONB) AS images
FROM cutoff.test_questions AS paper_question
JOIN cutoff.question_options AS option ON option.question_id = paper_question.question_id
LEFT JOIN cutoff.option_images AS option_image
  ON option_image.question_id = option.question_id AND option_image.option_label = option.option_label
WHERE paper_question.test_id = $1
GROUP BY paper_question.position, paper_question.question_id, option.option_label, option.option_text
ORDER BY paper_question.position, option.option_label;


-- @R7
-- READ R7 | Deliver ordered question images
-- Parameters: $1: test_id
PREPARE cutoff_r7(BIGINT) AS
SELECT paper_question.question_id, question_image.image_position, question_image.image_url
FROM cutoff.test_questions AS paper_question
JOIN cutoff.question_images AS question_image ON question_image.question_id = paper_question.question_id
WHERE paper_question.test_id = $1
ORDER BY paper_question.position, question_image.image_position;


-- @R8
-- READ R8 | Find the current resumable attempt
-- Parameters: $1: authenticated_user_id, $2: test_id
PREPARE cutoff_r8(BIGINT, BIGINT) AS
SELECT attempt.attempt_id, attempt.test_id, attempt.started_at, attempt.attempt_status,
       paper.duration_minutes,
       GREATEST(0, floor(extract(epoch FROM
           attempt.started_at + paper.duration_minutes * INTERVAL '1 minute' - clock_timestamp()
       )))::INTEGER AS remaining_seconds
FROM cutoff.attempts AS attempt
JOIN cutoff.tests AS paper ON paper.test_id = attempt.test_id
WHERE attempt.user_id = $1 AND attempt.test_id = $2 AND attempt.attempt_status = 'IN_PROGRESS'
  AND clock_timestamp() < attempt.started_at + paper.duration_minutes * INTERVAL '1 minute';


-- @R9
-- READ R9 | Read an owned attempt and its timer
-- Parameters: $1: authenticated_user_id, $2: attempt_id
PREPARE cutoff_r9(BIGINT, BIGINT) AS
SELECT attempt.attempt_id, attempt.test_id, paper.test_title, attempt.attempt_status,
       attempt.started_at, attempt.submitted_at, paper.duration_minutes,
       CASE WHEN attempt.attempt_status = 'SUBMITTED' THEN 0 ELSE
           GREATEST(0, floor(extract(epoch FROM
               attempt.started_at + paper.duration_minutes * INTERVAL '1 minute' - clock_timestamp()
           )))::INTEGER END AS remaining_seconds
FROM cutoff.attempts AS attempt
JOIN cutoff.tests AS paper ON paper.test_id = attempt.test_id
WHERE attempt.user_id = $1 AND attempt.attempt_id = $2;


-- @R10
-- READ R10 | Restore question navigation, review flags and saved responses
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- Left joins retain questions for which no answer has ever been saved.
PREPARE cutoff_r10(BIGINT, BIGINT) AS
SELECT paper_question.position, paper_question.question_id, question.question_type,
       answer.numerical_response,
       coalesce(answer.marked_for_review, false) AS marked_for_review,
       coalesce(answer.time_spent_seconds, 0) AS time_spent_seconds,
       answer.answer_updated_at,
       answer.attempt_id IS NOT NULL AS has_saved_state,
       ARRAY(SELECT selected.option_label FROM cutoff.answer_options AS selected
             WHERE selected.attempt_id = attempt.attempt_id AND selected.question_id = paper_question.question_id
             ORDER BY selected.option_label) AS selected_options
FROM cutoff.attempts AS attempt
JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id
JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
LEFT JOIN cutoff.answers AS answer
  ON answer.attempt_id = attempt.attempt_id AND answer.question_id = paper_question.question_id
WHERE attempt.user_id = $1 AND attempt.attempt_id = $2
ORDER BY paper_question.position;


-- @R11
-- READ R11 | Review and score every question in a submitted attempt
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- ARRAY collects labels into a sorted list; cardinality counts labels in that list.
-- Sorted lists must match exactly: selecting only A is wrong when the key is A,C.
-- BETWEEN includes both bounds; zero is a valid numerical response.
-- R12-R14 reuse these four steps, then summarize the scored rows.
PREPARE cutoff_r11(BIGINT, BIGINT) AS
-- Step 1: Find this student's submitted attempt(s).
WITH selected_attempts AS (
    SELECT attempt_id, test_id
    FROM cutoff.attempts
    WHERE user_id = $1 AND attempt_id = $2 AND attempt_status = 'SUBMITTED'
), answer_details AS (
    -- Step 2: Join questions, saved responses and answer keys.
    SELECT attempt.attempt_id, attempt.test_id, paper_question.position, question.question_id, question.question_text,
           question.explanation_text, question.question_type, question.difficulty,
           subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
           topic.topic_id, topic.topic_name,
           paper_question.marks_correct, paper_question.marks_incorrect, paper_question.marks_unattempted,
           answer.numerical_response,
           coalesce(answer.time_spent_seconds, 0) AS time_spent_seconds,
           number_key.accepted_min, number_key.accepted_max,
           ARRAY(SELECT selected.option_label FROM cutoff.answer_options AS selected
                 WHERE selected.attempt_id = attempt.attempt_id AND selected.question_id = question.question_id
                 ORDER BY selected.option_label) AS selected_options,
           ARRAY(SELECT answer_key.option_label FROM cutoff.correct_options AS answer_key
                 WHERE answer_key.question_id = question.question_id
                 ORDER BY answer_key.option_label) AS correct_options,
           (SELECT count(*) FROM cutoff.question_options AS option
            WHERE option.question_id = question.question_id) AS option_count
    FROM selected_attempts AS attempt
    JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id
    JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
    JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
    JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
    LEFT JOIN cutoff.question_topics AS question_topic ON question_topic.question_id = question.question_id
    LEFT JOIN cutoff.topics AS topic ON topic.topic_id = question_topic.topic_id
    LEFT JOIN cutoff.answers AS answer
      ON answer.attempt_id = attempt.attempt_id AND answer.question_id = question.question_id
    LEFT JOIN cutoff.numerical_keys AS number_key ON number_key.question_id = question.question_id
), evaluated_answers AS (
    -- Step 3: Label each response: correct, incorrect, unattempted or invalid_key.
    SELECT details.*,
           CASE
               WHEN question_type = 'NUMERICAL' AND
                    (accepted_min IS NULL OR option_count <> 0
                     OR cardinality(correct_options) <> 0) THEN 'invalid_key'
               WHEN question_type <> 'NUMERICAL' AND
                    (accepted_min IS NOT NULL OR option_count < 2
                     OR cardinality(correct_options) = 0
                     OR (question_type = 'SINGLE_CHOICE'
                         AND cardinality(correct_options) <> 1)) THEN 'invalid_key'
               WHEN question_type = 'NUMERICAL' AND numerical_response IS NULL
                    THEN 'unattempted'
               WHEN question_type <> 'NUMERICAL' AND cardinality(selected_options) = 0
                    THEN 'unattempted'
               WHEN question_type = 'NUMERICAL'
                    AND numerical_response BETWEEN accepted_min AND accepted_max THEN 'correct'
               WHEN question_type <> 'NUMERICAL' AND selected_options = correct_options
                    THEN 'correct'
               ELSE 'incorrect'
           END AS outcome
    FROM answer_details AS details
), scored_answers AS (
    -- Step 4: Assign the paper's marks to each outcome.
    SELECT evaluation.*,
           CASE outcome WHEN 'correct' THEN marks_correct
                        WHEN 'incorrect' THEN marks_incorrect
                        WHEN 'unattempted' THEN marks_unattempted
                        ELSE NULL END AS marks_awarded
    FROM evaluated_answers AS evaluation
)
SELECT position, question_id, question_text, question_type, difficulty,
       subject_name, chapter_name, topic_name,
       selected_options, numerical_response, correct_options, accepted_min, accepted_max,
       explanation_text, outcome, marks_awarded, marks_correct AS maximum_marks,
       time_spent_seconds
FROM scored_answers
ORDER BY position;


-- @R12
-- READ R12 | Calculate the result summary
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- NULL accuracy means no attempted questions; an invalid key makes score/accuracy NULL and must be flagged.
PREPARE cutoff_r12(BIGINT, BIGINT) AS
-- Step 1: Find this student's submitted attempt(s).
WITH selected_attempts AS (
    SELECT attempt_id, test_id
    FROM cutoff.attempts
    WHERE user_id = $1 AND attempt_id = $2 AND attempt_status = 'SUBMITTED'
), answer_details AS (
    -- Step 2: Join questions, saved responses and answer keys.
    SELECT attempt.attempt_id, attempt.test_id, paper_question.position, question.question_id, question.question_text,
           question.explanation_text, question.question_type, question.difficulty,
           subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
           topic.topic_id, topic.topic_name,
           paper_question.marks_correct, paper_question.marks_incorrect, paper_question.marks_unattempted,
           answer.numerical_response,
           coalesce(answer.time_spent_seconds, 0) AS time_spent_seconds,
           number_key.accepted_min, number_key.accepted_max,
           ARRAY(SELECT selected.option_label FROM cutoff.answer_options AS selected
                 WHERE selected.attempt_id = attempt.attempt_id AND selected.question_id = question.question_id
                 ORDER BY selected.option_label) AS selected_options,
           ARRAY(SELECT answer_key.option_label FROM cutoff.correct_options AS answer_key
                 WHERE answer_key.question_id = question.question_id
                 ORDER BY answer_key.option_label) AS correct_options,
           (SELECT count(*) FROM cutoff.question_options AS option
            WHERE option.question_id = question.question_id) AS option_count
    FROM selected_attempts AS attempt
    JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id
    JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
    JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
    JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
    LEFT JOIN cutoff.question_topics AS question_topic ON question_topic.question_id = question.question_id
    LEFT JOIN cutoff.topics AS topic ON topic.topic_id = question_topic.topic_id
    LEFT JOIN cutoff.answers AS answer
      ON answer.attempt_id = attempt.attempt_id AND answer.question_id = question.question_id
    LEFT JOIN cutoff.numerical_keys AS number_key ON number_key.question_id = question.question_id
), evaluated_answers AS (
    -- Step 3: Label each response: correct, incorrect, unattempted or invalid_key.
    SELECT details.*,
           CASE
               WHEN question_type = 'NUMERICAL' AND
                    (accepted_min IS NULL OR option_count <> 0
                     OR cardinality(correct_options) <> 0) THEN 'invalid_key'
               WHEN question_type <> 'NUMERICAL' AND
                    (accepted_min IS NOT NULL OR option_count < 2
                     OR cardinality(correct_options) = 0
                     OR (question_type = 'SINGLE_CHOICE'
                         AND cardinality(correct_options) <> 1)) THEN 'invalid_key'
               WHEN question_type = 'NUMERICAL' AND numerical_response IS NULL
                    THEN 'unattempted'
               WHEN question_type <> 'NUMERICAL' AND cardinality(selected_options) = 0
                    THEN 'unattempted'
               WHEN question_type = 'NUMERICAL'
                    AND numerical_response BETWEEN accepted_min AND accepted_max THEN 'correct'
               WHEN question_type <> 'NUMERICAL' AND selected_options = correct_options
                    THEN 'correct'
               ELSE 'incorrect'
           END AS outcome
    FROM answer_details AS details
), scored_answers AS (
    -- Step 4: Assign the paper's marks to each outcome.
    SELECT evaluation.*,
           CASE outcome WHEN 'correct' THEN marks_correct
                        WHEN 'incorrect' THEN marks_incorrect
                        WHEN 'unattempted' THEN marks_unattempted
                        ELSE NULL END AS marks_awarded
    FROM evaluated_answers AS evaluation
)
SELECT attempt_id, count(*) AS question_count,
       COUNT(CASE WHEN outcome = 'correct' THEN 1 END) AS correct_count,
       COUNT(CASE WHEN outcome = 'incorrect' THEN 1 END) AS incorrect_count,
       COUNT(CASE WHEN outcome = 'unattempted' THEN 1 END) AS skipped_count,
       COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) AS invalid_key_count,
       CASE WHEN COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) = 0
            THEN sum(marks_awarded) END AS score,
       sum(marks_correct) AS maximum_marks,
       CASE WHEN COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) = 0 THEN
           round(100.0 * COUNT(CASE WHEN outcome = 'correct' THEN 1 END) /
                 nullif(COUNT(CASE WHEN outcome IN ('correct', 'incorrect') THEN 1 END), 0), 2)
       END AS accuracy_percent,
       sum(time_spent_seconds) AS total_time_seconds
FROM scored_answers
GROUP BY attempt_id;


-- @R13
-- READ R13 | Analyse subject, chapter, topic, difficulty and time usage
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- Counts are per dimension. Do not sum subject, chapter, topic and difficulty rows together.
PREPARE cutoff_r13(BIGINT, BIGINT) AS
-- Step 1: Find this student's submitted attempt(s).
WITH selected_attempts AS (
    SELECT attempt_id, test_id
    FROM cutoff.attempts
    WHERE user_id = $1 AND attempt_id = $2 AND attempt_status = 'SUBMITTED'
), answer_details AS (
    -- Step 2: Join questions, saved responses and answer keys.
    SELECT attempt.attempt_id, attempt.test_id, paper_question.position, question.question_id, question.question_text,
           question.explanation_text, question.question_type, question.difficulty,
           subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
           topic.topic_id, topic.topic_name,
           paper_question.marks_correct, paper_question.marks_incorrect, paper_question.marks_unattempted,
           answer.numerical_response,
           coalesce(answer.time_spent_seconds, 0) AS time_spent_seconds,
           number_key.accepted_min, number_key.accepted_max,
           ARRAY(SELECT selected.option_label FROM cutoff.answer_options AS selected
                 WHERE selected.attempt_id = attempt.attempt_id AND selected.question_id = question.question_id
                 ORDER BY selected.option_label) AS selected_options,
           ARRAY(SELECT answer_key.option_label FROM cutoff.correct_options AS answer_key
                 WHERE answer_key.question_id = question.question_id
                 ORDER BY answer_key.option_label) AS correct_options,
           (SELECT count(*) FROM cutoff.question_options AS option
            WHERE option.question_id = question.question_id) AS option_count
    FROM selected_attempts AS attempt
    JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id
    JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
    JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
    JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
    LEFT JOIN cutoff.question_topics AS question_topic ON question_topic.question_id = question.question_id
    LEFT JOIN cutoff.topics AS topic ON topic.topic_id = question_topic.topic_id
    LEFT JOIN cutoff.answers AS answer
      ON answer.attempt_id = attempt.attempt_id AND answer.question_id = question.question_id
    LEFT JOIN cutoff.numerical_keys AS number_key ON number_key.question_id = question.question_id
), evaluated_answers AS (
    -- Step 3: Label each response: correct, incorrect, unattempted or invalid_key.
    SELECT details.*,
           CASE
               WHEN question_type = 'NUMERICAL' AND
                    (accepted_min IS NULL OR option_count <> 0
                     OR cardinality(correct_options) <> 0) THEN 'invalid_key'
               WHEN question_type <> 'NUMERICAL' AND
                    (accepted_min IS NOT NULL OR option_count < 2
                     OR cardinality(correct_options) = 0
                     OR (question_type = 'SINGLE_CHOICE'
                         AND cardinality(correct_options) <> 1)) THEN 'invalid_key'
               WHEN question_type = 'NUMERICAL' AND numerical_response IS NULL
                    THEN 'unattempted'
               WHEN question_type <> 'NUMERICAL' AND cardinality(selected_options) = 0
                    THEN 'unattempted'
               WHEN question_type = 'NUMERICAL'
                    AND numerical_response BETWEEN accepted_min AND accepted_max THEN 'correct'
               WHEN question_type <> 'NUMERICAL' AND selected_options = correct_options
                    THEN 'correct'
               ELSE 'incorrect'
           END AS outcome
    FROM answer_details AS details
), scored_answers AS (
    -- Step 4: Assign the paper's marks to each outcome.
    SELECT evaluation.*,
           CASE outcome WHEN 'correct' THEN marks_correct
                        WHEN 'incorrect' THEN marks_incorrect
                        WHEN 'unattempted' THEN marks_unattempted
                        ELSE NULL END AS marks_awarded
    FROM evaluated_answers AS evaluation
), analysis_groups AS (
    -- Each question contributes once to each of the four separate reports.
    SELECT scored_answers.*, 'subject' AS dimension, subject_id AS group_id,
           subject_name AS group_name
    FROM scored_answers
    UNION ALL
    SELECT scored_answers.*, 'chapter', chapter_id, chapter_name
    FROM scored_answers
    UNION ALL
    SELECT scored_answers.*, 'topic', topic_id, COALESCE(topic_name, 'Unclassified topic')
    FROM scored_answers
    UNION ALL
    SELECT scored_answers.*, 'difficulty', CAST(NULL AS BIGINT), difficulty
    FROM scored_answers
)
SELECT dimension, group_id, group_name,
       count(*) AS question_count,
       COUNT(CASE WHEN outcome = 'correct' THEN 1 END) AS correct_count,
       COUNT(CASE WHEN outcome = 'incorrect' THEN 1 END) AS incorrect_count,
       COUNT(CASE WHEN outcome = 'unattempted' THEN 1 END) AS skipped_count,
       COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) AS invalid_key_count,
       CASE WHEN COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) = 0
            THEN sum(marks_awarded) END AS score,
       sum(marks_correct) AS maximum_marks,
       CASE WHEN COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) = 0 THEN
           round(100.0 * COUNT(CASE WHEN outcome = 'correct' THEN 1 END) /
                 nullif(COUNT(CASE WHEN outcome IN ('correct', 'incorrect') THEN 1 END), 0), 2)
       END AS accuracy_percent,
       sum(time_spent_seconds) AS total_time_seconds,
       SUM(CASE WHEN outcome = 'correct' THEN time_spent_seconds ELSE 0 END) AS time_on_correct_seconds,
       SUM(CASE WHEN outcome = 'incorrect' THEN time_spent_seconds ELSE 0 END) AS time_on_incorrect_seconds,
       SUM(CASE WHEN outcome = 'unattempted' THEN time_spent_seconds ELSE 0 END) AS time_on_skipped_seconds,
       COUNT(CASE WHEN time_spent_seconds > 180 THEN 1 END) AS slow_question_count
FROM analysis_groups
GROUP BY dimension, group_id, group_name
ORDER BY dimension, group_name, group_id;


-- @R14
-- READ R14 | List a student's attempt history with submitted result summaries
-- Parameters: $1: authenticated_user_id, $2: test_id or NULL, $3: status or NULL, $4: limit, $5: offset
-- In-progress attempts have no score or correctness counts; saved state does not necessarily mean answered.
PREPARE cutoff_r14(BIGINT, BIGINT, TEXT, INTEGER, INTEGER) AS
-- Step 1: Find this student's submitted attempt(s).
WITH selected_attempts AS (
    SELECT attempt_id, test_id
    FROM cutoff.attempts
    WHERE user_id = $1 AND attempt_status = 'SUBMITTED'
      AND ($2 IS NULL OR test_id = $2)
      AND ($3 IS NULL OR attempt_status = $3)
), answer_details AS (
    -- Step 2: Join questions, saved responses and answer keys.
    SELECT attempt.attempt_id, attempt.test_id, paper_question.position, question.question_id, question.question_text,
           question.explanation_text, question.question_type, question.difficulty,
           subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
           topic.topic_id, topic.topic_name,
           paper_question.marks_correct, paper_question.marks_incorrect, paper_question.marks_unattempted,
           answer.numerical_response,
           coalesce(answer.time_spent_seconds, 0) AS time_spent_seconds,
           number_key.accepted_min, number_key.accepted_max,
           ARRAY(SELECT selected.option_label FROM cutoff.answer_options AS selected
                 WHERE selected.attempt_id = attempt.attempt_id AND selected.question_id = question.question_id
                 ORDER BY selected.option_label) AS selected_options,
           ARRAY(SELECT answer_key.option_label FROM cutoff.correct_options AS answer_key
                 WHERE answer_key.question_id = question.question_id
                 ORDER BY answer_key.option_label) AS correct_options,
           (SELECT count(*) FROM cutoff.question_options AS option
            WHERE option.question_id = question.question_id) AS option_count
    FROM selected_attempts AS attempt
    JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id
    JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
    JOIN cutoff.chapters AS chapter ON chapter.chapter_id = question.chapter_id
    JOIN cutoff.subjects AS subject ON subject.subject_id = chapter.subject_id
    LEFT JOIN cutoff.question_topics AS question_topic ON question_topic.question_id = question.question_id
    LEFT JOIN cutoff.topics AS topic ON topic.topic_id = question_topic.topic_id
    LEFT JOIN cutoff.answers AS answer
      ON answer.attempt_id = attempt.attempt_id AND answer.question_id = question.question_id
    LEFT JOIN cutoff.numerical_keys AS number_key ON number_key.question_id = question.question_id
), evaluated_answers AS (
    -- Step 3: Label each response: correct, incorrect, unattempted or invalid_key.
    SELECT details.*,
           CASE
               WHEN question_type = 'NUMERICAL' AND
                    (accepted_min IS NULL OR option_count <> 0
                     OR cardinality(correct_options) <> 0) THEN 'invalid_key'
               WHEN question_type <> 'NUMERICAL' AND
                    (accepted_min IS NOT NULL OR option_count < 2
                     OR cardinality(correct_options) = 0
                     OR (question_type = 'SINGLE_CHOICE'
                         AND cardinality(correct_options) <> 1)) THEN 'invalid_key'
               WHEN question_type = 'NUMERICAL' AND numerical_response IS NULL
                    THEN 'unattempted'
               WHEN question_type <> 'NUMERICAL' AND cardinality(selected_options) = 0
                    THEN 'unattempted'
               WHEN question_type = 'NUMERICAL'
                    AND numerical_response BETWEEN accepted_min AND accepted_max THEN 'correct'
               WHEN question_type <> 'NUMERICAL' AND selected_options = correct_options
                    THEN 'correct'
               ELSE 'incorrect'
           END AS outcome
    FROM answer_details AS details
), scored_answers AS (
    -- Step 4: Assign the paper's marks to each outcome.
    SELECT evaluation.*,
           CASE outcome WHEN 'correct' THEN marks_correct
                        WHEN 'incorrect' THEN marks_incorrect
                        WHEN 'unattempted' THEN marks_unattempted
                        ELSE NULL END AS marks_awarded
    FROM evaluated_answers AS evaluation
), totals AS (
    SELECT attempt_id,
           COUNT(CASE WHEN outcome = 'correct' THEN 1 END) AS correct_count,
           COUNT(CASE WHEN outcome = 'incorrect' THEN 1 END) AS incorrect_count,
           COUNT(CASE WHEN outcome = 'unattempted' THEN 1 END) AS skipped_count,
           COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) AS invalid_key_count,
           CASE WHEN COUNT(CASE WHEN outcome = 'invalid_key' THEN 1 END) = 0
                THEN sum(marks_awarded) END AS score,
           sum(marks_correct) AS maximum_marks
    FROM scored_answers
GROUP BY attempt_id
)
SELECT attempt.attempt_id, attempt.test_id, paper.test_title, attempt.attempt_status,
       attempt.started_at, attempt.submitted_at,
       totals.score, totals.maximum_marks, totals.correct_count,
       totals.incorrect_count, totals.skipped_count, totals.invalid_key_count,
       (SELECT count(*) FROM cutoff.answers AS answer
        WHERE answer.attempt_id = attempt.attempt_id) AS saved_question_states
FROM cutoff.attempts AS attempt
JOIN cutoff.tests AS paper ON paper.test_id = attempt.test_id
LEFT JOIN totals ON totals.attempt_id = attempt.attempt_id
WHERE attempt.user_id = $1 AND ($2 IS NULL OR attempt.test_id = $2)
  AND ($3 IS NULL OR attempt.attempt_status = $3)
ORDER BY attempt.started_at DESC, attempt.attempt_id DESC
LIMIT LEAST(GREATEST(COALESCE($4, 20), 1), 100)
OFFSET GREATEST(COALESCE($5, 0), 0);


-- @R15
-- READ R15 | Resolve the shared subject/chapter/topic taxonomy
-- Parameters: none
PREPARE cutoff_r15 AS
SELECT subject.subject_id, subject.subject_name, chapter.chapter_id, chapter.chapter_name,
       topic.topic_id, topic.topic_name
FROM cutoff.subjects AS subject
LEFT JOIN cutoff.chapters AS chapter ON chapter.subject_id = subject.subject_id
LEFT JOIN cutoff.topics AS topic ON topic.chapter_id = chapter.chapter_id
ORDER BY subject.subject_name, chapter.chapter_name, topic.topic_name;


-- @R16
-- READ R16 | Validate a new paper before committing its import
-- Parameters: $1: test_id
-- Trusted importer only. Zero rows means these structural checks pass; content verification is still required.
PREPARE cutoff_r16(BIGINT) AS
WITH inspection AS (
    SELECT question.question_id, question.question_type,
           (SELECT count(*) FROM cutoff.question_options AS option
            WHERE option.question_id = question.question_id) AS option_count,
           (SELECT count(*) FROM cutoff.correct_options AS answer_key
            WHERE answer_key.question_id = question.question_id) AS correct_count,
           EXISTS (SELECT 1 FROM cutoff.numerical_keys AS number_key
                   WHERE number_key.question_id = question.question_id) AS has_numerical_key,
           EXISTS (SELECT 1 FROM cutoff.question_options AS option
                   WHERE option.question_id = question.question_id AND TRIM(option.option_text) = ''
                     AND NOT EXISTS (SELECT 1 FROM cutoff.option_images AS option_image
                                     WHERE option_image.question_id = option.question_id
                                       AND option_image.option_label = option.option_label)) AS empty_option
    FROM cutoff.test_questions AS paper_question
    JOIN cutoff.questions AS question ON question.question_id = paper_question.question_id
    WHERE paper_question.test_id = $1
), issues AS (
    SELECT NULL::BIGINT AS question_id, 'test_not_found' AS issue
    WHERE NOT EXISTS (SELECT 1 FROM cutoff.tests WHERE test_id = $1)
    UNION ALL
    SELECT NULL::BIGINT, 'paper_has_no_questions'
    WHERE EXISTS (SELECT 1 FROM cutoff.tests WHERE test_id = $1)
      AND NOT EXISTS (SELECT 1 FROM inspection)
    UNION ALL
    SELECT question_id, 'invalid_question_key_or_options'
    FROM inspection
    WHERE (question_type = 'NUMERICAL'
           AND (NOT has_numerical_key OR option_count <> 0 OR correct_count <> 0))
       OR (question_type = 'SINGLE_CHOICE'
           AND (has_numerical_key OR option_count < 2 OR correct_count <> 1))
       OR (question_type = 'MULTIPLE_SELECT'
           AND (has_numerical_key OR option_count < 2 OR correct_count < 1))
       OR empty_option
)
SELECT question_id, issue FROM issues ORDER BY question_id NULLS FIRST, issue;


-- @R17
-- READ R17 | Lock an owned active attempt before saving or submitting
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- Run inside BEGIN/COMMIT. This SELECT takes a row lock; an expired attempt can only be submitted, not saved.
PREPARE cutoff_r17(BIGINT, BIGINT) AS
SELECT attempt.attempt_id, attempt.test_id, attempt.started_at,
       attempt.started_at + paper.duration_minutes * INTERVAL '1 minute' AS expires_at,
       clock_timestamp() >= attempt.started_at + paper.duration_minutes * INTERVAL '1 minute' AS expired
FROM cutoff.attempts AS attempt
JOIN cutoff.tests AS paper ON paper.test_id = attempt.test_id
WHERE attempt.user_id = $1 AND attempt.attempt_id = $2 AND attempt.attempt_status = 'IN_PROGRESS'
FOR UPDATE OF attempt;


-- @R18
-- READ R18 | Check database connectivity
-- Parameters: none
PREPARE cutoff_r18 AS
SELECT 1 AS database_ready;


-- @W1
-- WRITE W1 | Register a student with a backend-generated password hash
-- Parameters: $1: name, $2: email, $3: password_hash
PREPARE cutoff_w1(TEXT, TEXT, TEXT) AS
INSERT INTO cutoff.users(user_name, email, password_hash)
VALUES (TRIM($1), lower(TRIM($2)), $3)
RETURNING user_id, user_name, email, user_created_at;


-- @W2
-- WRITE W2 | Create an attempt if this student has no active attempt on the paper
-- Parameters: $1: authenticated_user_id, $2: test_id
-- If no row is inserted, use R8 to find an existing active attempt. If R8 is also empty, reject the start.
PREPARE cutoff_w2(BIGINT, BIGINT) AS
INSERT INTO cutoff.attempts(user_id, test_id)
SELECT student.user_id, paper.test_id
FROM cutoff.users AS student CROSS JOIN cutoff.tests AS paper
WHERE student.user_id = $1 AND paper.test_id = $2
  AND EXISTS (SELECT 1 FROM cutoff.test_questions AS paper_question WHERE paper_question.test_id = paper.test_id)
ON CONFLICT (user_id, test_id) WHERE attempt_status = 'IN_PROGRESS' DO NOTHING
RETURNING attempt_id, user_id, test_id, started_at, attempt_status;


-- @W3
-- WRITE W3 | Save numerical/choice answer state, review flag and cumulative time
-- Parameters: $1: authenticated_user_id, $2: attempt_id, $3: question_id, $4: number or NULL, $5: review flag, $6: cumulative seconds
-- Use R17 -> W3 -> W4 -> W5 in one transaction; require one returned row before continuing.
PREPARE cutoff_w3(BIGINT, BIGINT, BIGINT, NUMERIC, BOOLEAN, INTEGER) AS
INSERT INTO cutoff.answers AS existing
    (attempt_id, question_id, numerical_response, marked_for_review, time_spent_seconds)
SELECT attempt.attempt_id, paper_question.question_id, $4, $5, $6
FROM cutoff.attempts AS attempt
JOIN cutoff.tests AS paper ON paper.test_id = attempt.test_id
JOIN cutoff.test_questions AS paper_question ON paper_question.test_id = attempt.test_id AND paper_question.question_id = $3
WHERE attempt.user_id = $1 AND attempt.attempt_id = $2 AND attempt.attempt_status = 'IN_PROGRESS'
  AND clock_timestamp() < attempt.started_at + paper.duration_minutes * INTERVAL '1 minute'
-- First save inserts a row; later saves update the same attempt/question pair.
-- EXCLUDED means the new values; existing means the row already stored.
ON CONFLICT (attempt_id, question_id) DO UPDATE
SET numerical_response = EXCLUDED.numerical_response,
    marked_for_review = EXCLUDED.marked_for_review,
    time_spent_seconds = GREATEST(existing.time_spent_seconds, EXCLUDED.time_spent_seconds)
RETURNING attempt_id, question_id, numerical_response, marked_for_review,
          time_spent_seconds, answer_updated_at;


-- @W4
-- WRITE W4 | Remove the old selected options before replacing or clearing an answer
-- Parameters: $1: authenticated_user_id, $2: attempt_id, $3: question_id
PREPARE cutoff_w4(BIGINT, BIGINT, BIGINT) AS
DELETE FROM cutoff.answer_options AS selected
USING cutoff.attempts AS attempt
WHERE selected.attempt_id = attempt.attempt_id
  AND attempt.user_id = $1 AND attempt.attempt_id = $2 AND selected.question_id = $3
  AND attempt.attempt_status = 'IN_PROGRESS'
RETURNING selected.attempt_id, selected.question_id, selected.option_label;


-- @W5
-- WRITE W5 | Insert the complete replacement set of selected options
-- Parameters: $1: authenticated_user_id, $2: attempt_id, $3: question_id, $4: selected_options text[]
-- Run only after W4 in the same transaction. Invalid labels/type/cardinality abort the save; roll back everything.
PREPARE cutoff_w5(BIGINT, BIGINT, BIGINT, TEXT[]) AS
INSERT INTO cutoff.answer_options(attempt_id, question_id, option_label)
SELECT DISTINCT attempt.attempt_id, answer.question_id, upper(TRIM(selection.option_label))
FROM cutoff.attempts AS attempt
JOIN cutoff.answers AS answer ON answer.attempt_id = attempt.attempt_id AND answer.question_id = $3
-- unnest turns an input list such as ARRAY['A', 'C'] into one row per label.
CROSS JOIN unnest($4) AS selection(option_label)
WHERE attempt.user_id = $1 AND attempt.attempt_id = $2 AND attempt.attempt_status = 'IN_PROGRESS'
RETURNING attempt_id, question_id, option_label;


-- @W6
-- WRITE W6 | Submit an owned active attempt
-- Parameters: $1: authenticated_user_id, $2: attempt_id
-- R17 holds the parent lock until COMMIT; derive results using R11-R13 afterwards.
PREPARE cutoff_w6(BIGINT, BIGINT) AS
UPDATE cutoff.attempts
SET attempt_status = 'SUBMITTED', submitted_at = clock_timestamp()
WHERE user_id = $1 AND attempt_id = $2 AND attempt_status = 'IN_PROGRESS'
RETURNING attempt_id, test_id, attempt_status, started_at, submitted_at;


-- @W7
-- WRITE W7 | Close an expired active attempt before starting another
-- Parameters: $1: authenticated_user_id, $2: test_id
PREPARE cutoff_w7(BIGINT, BIGINT) AS
UPDATE cutoff.attempts AS attempt
SET attempt_status = 'SUBMITTED', submitted_at = clock_timestamp()
FROM cutoff.tests AS paper
WHERE paper.test_id = attempt.test_id AND attempt.user_id = $1 AND attempt.test_id = $2
  AND attempt.attempt_status = 'IN_PROGRESS'
  AND clock_timestamp() >= attempt.started_at + paper.duration_minutes * INTERVAL '1 minute'
RETURNING attempt.attempt_id, attempt.test_id, attempt.attempt_status, attempt.submitted_at;


-- @W8
-- WRITE W8 | Create a taxonomy subject if it does not already exist
-- Parameters: $1: canonical subject name
-- R15 resolves the ID if the canonical subject already exists.
PREPARE cutoff_w8(TEXT) AS
INSERT INTO cutoff.subjects(subject_name) VALUES (TRIM($1))
ON CONFLICT (subject_name) DO NOTHING
RETURNING subject_id, subject_name;


-- @W9
-- WRITE W9 | Create a chapter within its subject
-- Parameters: $1: subject_id, $2: canonical chapter name
PREPARE cutoff_w9(BIGINT, TEXT) AS
INSERT INTO cutoff.chapters(subject_id, chapter_name) VALUES ($1, TRIM($2))
ON CONFLICT (subject_id, chapter_name) DO NOTHING
RETURNING chapter_id, subject_id, chapter_name;


-- @W10
-- WRITE W10 | Create a topic within its chapter
-- Parameters: $1: chapter_id, $2: canonical topic name
PREPARE cutoff_w10(BIGINT, TEXT) AS
INSERT INTO cutoff.topics(chapter_id, topic_name) VALUES ($1, TRIM($2))
ON CONFLICT (chapter_id, topic_name) DO NOTHING
RETURNING topic_id, chapter_id, topic_name;


-- @W11
-- WRITE W11 | Create a new verified question/version
-- Parameters: $1: chapter_id, $2: question text, $3: question type, $4: difficulty, $5: explanation or NULL
PREPARE cutoff_w11(BIGINT, TEXT, TEXT, TEXT, TEXT) AS
INSERT INTO cutoff.questions(chapter_id, question_text, question_type, difficulty, explanation_text)
VALUES ($1, $2, $3, $4, $5)
RETURNING question_id, chapter_id, question_type;


-- @W12
-- WRITE W12 | Assign the new question its optional primary topic
-- Parameters: $1: new_question_id, $2: topic_id
PREPARE cutoff_w12(BIGINT, BIGINT) AS
INSERT INTO cutoff.question_topics(question_id, topic_id) VALUES ($1, $2)
RETURNING question_id, topic_id;


-- @W13
-- WRITE W13 | Add one option to a new choice question
-- Parameters: $1: new_question_id, $2: option label, $3: option text
PREPARE cutoff_w13(BIGINT, TEXT, TEXT) AS
INSERT INTO cutoff.question_options(question_id, option_label, option_text)
VALUES ($1, upper(TRIM($2)), $3)
RETURNING question_id, option_label;


-- @W14
-- WRITE W14 | Record a correct option for a new choice question
-- Parameters: $1: new_question_id, $2: correct option label
PREPARE cutoff_w14(BIGINT, TEXT) AS
INSERT INTO cutoff.correct_options(question_id, option_label)
VALUES ($1, upper(TRIM($2)))
RETURNING question_id, option_label;


-- @W15
-- WRITE W15 | Record an inclusive numerical answer range
-- Parameters: $1: new_question_id, $2: accepted_min, $3: accepted_max
-- Equal bounds represent an exact answer; store any accepted tolerance explicitly in the bounds.
PREPARE cutoff_w15(BIGINT, NUMERIC, NUMERIC) AS
INSERT INTO cutoff.numerical_keys(question_id, accepted_min, accepted_max)
VALUES ($1, $2, $3)
RETURNING question_id, accepted_min, accepted_max;


-- @W16
-- WRITE W16 | Add an ordered image to a new question
-- Parameters: $1: new_question_id, $2: image position, $3: image URL
PREPARE cutoff_w16(BIGINT, INTEGER, TEXT) AS
INSERT INTO cutoff.question_images(question_id, image_position, image_url)
VALUES ($1, $2, $3)
RETURNING question_id, image_position;


-- @W17
-- WRITE W17 | Add an ordered image to a new option
-- Parameters: $1: new_question_id, $2: option label, $3: image position, $4: image URL
PREPARE cutoff_w17(BIGINT, TEXT, INTEGER, TEXT) AS
INSERT INTO cutoff.option_images(question_id, option_label, image_position, image_url)
VALUES ($1, upper(TRIM($2)), $3, $4)
RETURNING question_id, option_label, image_position;


-- @W18
-- WRITE W18 | Create a new historical paper/version
-- Parameters: $1: title, $2: exam year, $3: session label, $4: duration minutes
-- Use the returned ID; title is not a unique identifier.
PREPARE cutoff_w18(TEXT, SMALLINT, TEXT, INTEGER) AS
INSERT INTO cutoff.tests(test_title, exam_year, session_label, duration_minutes)
VALUES ($1, $2, $3, $4)
RETURNING test_id, test_title, exam_year, session_label, duration_minutes;


-- @W19
-- WRITE W19 | Place a verified question in the new paper with its marking rules
-- Parameters: $1: new_test_id, $2: question_id, $3: position, $4: correct marks, $5: incorrect marks, $6: unattempted marks
-- Incorrect marks are already negative, e.g. 4, -1, 0. Complete R16 before committing the import.
PREPARE cutoff_w19(BIGINT, BIGINT, INTEGER, NUMERIC, NUMERIC, NUMERIC) AS
INSERT INTO cutoff.test_questions
    (test_id, question_id, position, marks_correct, marks_incorrect, marks_unattempted)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING test_id, question_id, position;
