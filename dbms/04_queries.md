# CP3 Query Catalogue

This catalogue documents the 37 prepared statements currently present in [`04_queries.sql`](04_queries.sql). Names, operations, parameter order and table references were read from that file; the query logic below summarizes those statements without changing them. `R` means READ and `W` means WRITE. R17 is a READ that takes a row lock and belongs inside a transaction.

## R1 — Find an account for login or duplicate-email checking

- **Operation:** READ
- **Purpose and logic:** Finds the account row matching a normalized email address for backend login or duplicate-email checking.
- **Parameters:** `$1: email`
- **Tables:** `cutoff.users`
- **Source:** [`04_queries.sql` line 64](04_queries.sql#L64)

## R2 — Read the signed-in student profile

- **Operation:** READ
- **Purpose and logic:** Fetches the signed-in user profile by user ID.
- **Parameters:** `$1: authenticated_user_id`
- **Tables:** `cutoff.users`
- **Source:** [`04_queries.sql` line 74](04_queries.sql#L74)

## R3 — Browse papers with optional filters and pagination

- **Operation:** READ
- **Purpose and logic:** Joins papers to their question placements, applies optional year/session/title filters, groups counts and maximum marks, sorts newest papers first, and paginates.
- **Parameters:** `$1: year or NULL, $2: session or NULL, $3: title search or NULL, $4: limit, $5: offset`
- **Tables:** `cutoff.test_questions`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 83](04_queries.sql#L83)

## R4 — Read paper details and subject-wise question/mark counts

- **Operation:** READ
- **Purpose and logic:** Returns one paper and its question count and maximum marks grouped by subject; the left joins preserve papers with no matching questions or subject.
- **Parameters:** `$1: test_id`
- **Tables:** `cutoff.chapters`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 101](04_queries.sql#L101)

## R5 — Deliver paper questions without answers or explanations

- **Operation:** READ
- **Purpose and logic:** Returns ordered paper questions with subject/chapter/topic and marking metadata while omitting answer keys and explanations.
- **Parameters:** `$1: test_id`
- **Tables:** `cutoff.chapters`, `cutoff.question_topics`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 119](04_queries.sql#L119)

## R6 — Deliver choice options and their ordered images

- **Operation:** READ
- **Purpose and logic:** Returns each choice option for a paper and aggregates any option images into an ordered JSON array.
- **Parameters:** `$1: test_id`
- **Tables:** `cutoff.option_images`, `cutoff.question_options`, `cutoff.test_questions`
- **Source:** [`04_queries.sql` line 137](04_queries.sql#L137)

## R7 — Deliver ordered question images

- **Operation:** READ
- **Purpose and logic:** Returns question images in paper and image order.
- **Parameters:** `$1: test_id`
- **Tables:** `cutoff.question_images`, `cutoff.test_questions`
- **Source:** [`04_queries.sql` line 157](04_queries.sql#L157)

## R8 — Find the current resumable attempt

- **Operation:** READ
- **Purpose and logic:** Finds a student’s active, unexpired attempt for a paper and computes remaining seconds.
- **Parameters:** `$1: authenticated_user_id, $2: test_id`
- **Tables:** `cutoff.attempts`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 168](04_queries.sql#L168)

## R9 — Read an owned attempt and its timer

- **Operation:** READ
- **Purpose and logic:** Fetches one owned attempt, paper details, and remaining time (zero after submission).
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.attempts`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 183](04_queries.sql#L183)

## R10 — Restore question navigation, review flags and saved responses

- **Operation:** READ
- **Purpose and logic:** Restores the paper’s question order and each question’s saved numerical response, selected options, review flag, time and saved-state indicator.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`, `cutoff.questions`, `cutoff.test_questions`
- **Source:** [`04_queries.sql` line 198](04_queries.sql#L198)

## R11 — Review and score every question in a submitted attempt

- **Operation:** READ
- **Purpose and logic:** Builds question-level answer details for an owned submitted attempt, validates keys, labels outcomes, and applies paper-specific marks.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`, `cutoff.chapters`, `cutoff.correct_options`, `cutoff.numerical_keys`, `cutoff.question_options`, `cutoff.question_topics`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 221](04_queries.sql#L221)

## R12 — Calculate the result summary

- **Operation:** READ
- **Purpose and logic:** Aggregates the scored question rows into score, maximum marks, correctness counts, accuracy, time totals and slow-question count; invalid keys suppress the score.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`, `cutoff.chapters`, `cutoff.correct_options`, `cutoff.numerical_keys`, `cutoff.question_options`, `cutoff.question_topics`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 303](04_queries.sql#L303)

## R13 — Analyse subject, chapter, topic, difficulty and time usage

- **Operation:** READ
- **Purpose and logic:** Builds the same submitted-attempt evaluation and groups performance by subject, chapter, topic and difficulty, including outcome and time metrics.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`, `cutoff.chapters`, `cutoff.correct_options`, `cutoff.numerical_keys`, `cutoff.question_options`, `cutoff.question_topics`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 390](04_queries.sql#L390)

## R14 — List a student's attempt history with submitted result summaries

- **Operation:** READ
- **Purpose and logic:** Lists the authenticated student’s attempts with submitted-result summaries, optional test/status filters, and pagination.
- **Parameters:** `$1: authenticated_user_id, $2: test_id or NULL, $3: status or NULL, $4: limit, $5: offset`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`, `cutoff.chapters`, `cutoff.correct_options`, `cutoff.numerical_keys`, `cutoff.question_options`, `cutoff.question_topics`, `cutoff.questions`, `cutoff.subjects`, `cutoff.test_questions`, `cutoff.tests`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 497](04_queries.sql#L497)

## R15 — Resolve the shared subject/chapter/topic taxonomy

- **Operation:** READ
- **Purpose and logic:** Lists the subject/chapter/topic taxonomy in name order, retaining subjects without chapters and chapters without topics.
- **Parameters:** `none`
- **Tables:** `cutoff.chapters`, `cutoff.subjects`, `cutoff.topics`
- **Source:** [`04_queries.sql` line 596](04_queries.sql#L596)

## R16 — Validate a new paper before committing its import

- **Operation:** READ
- **Purpose and logic:** Checks that a paper exists, has questions, and each included question has a structurally valid key/options setup; returns issues, with zero rows meaning these checks pass.
- **Parameters:** `$1: test_id`
- **Tables:** `cutoff.correct_options`, `cutoff.numerical_keys`, `cutoff.option_images`, `cutoff.question_options`, `cutoff.questions`, `cutoff.test_questions`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 608](04_queries.sql#L608)

## R17 — Lock an owned active attempt before saving or submitting

- **Operation:** READ
- **Purpose and logic:** Selects and row-locks the authenticated student’s active attempt, returning its deadline and expired flag for a save/submit transaction.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.attempts`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 650](04_queries.sql#L650)

## R18 — Check database connectivity

- **Operation:** READ
- **Purpose and logic:** Returns a constant readiness value as a database connectivity probe.
- **Parameters:** `none`
- **Tables:** none
- **Source:** [`04_queries.sql` line 664](04_queries.sql#L664)

## W1 — Register a student with a backend-generated password hash

- **Operation:** WRITE
- **Purpose and logic:** Creates a student account after trimming the name/email, lowercasing the email, and storing the backend-generated password hash.
- **Parameters:** `$1: name, $2: email, $3: password_hash`
- **Tables:** `cutoff.users`
- **Source:** [`04_queries.sql` line 671](04_queries.sql#L671)

## W2 — Create an attempt if this student has no active attempt on the paper

- **Operation:** WRITE
- **Purpose and logic:** Creates an active attempt only when the student and paper exist, the paper has questions, and no active attempt already exists for that student/paper.
- **Parameters:** `$1: authenticated_user_id, $2: test_id`
- **Tables:** `cutoff.attempts`, `cutoff.test_questions`, `cutoff.tests`, `cutoff.users`
- **Source:** [`04_queries.sql` line 680](04_queries.sql#L680)

## W3 — Save numerical/choice answer state, review flag and cumulative time

- **Operation:** WRITE
- **Purpose and logic:** Inserts or updates one owned active-attempt answer state, applies the deadline check, and keeps cumulative time from decreasing.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id, $3: question_id, $4: number or NULL, $5: review flag, $6: cumulative seconds`
- **Tables:** `cutoff.answers`, `cutoff.attempts`, `cutoff.test_questions`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 694](04_queries.sql#L694)

## W4 — Remove the old selected options before replacing or clearing an answer

- **Operation:** WRITE
- **Purpose and logic:** Deletes selected option rows for one owned active attempt and question so the caller can replace or clear the selection set.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id, $3: question_id`
- **Tables:** `cutoff.answer_options`, `cutoff.attempts`
- **Source:** [`04_queries.sql` line 717](04_queries.sql#L717)

## W5 — Insert the complete replacement set of selected options

- **Operation:** WRITE
- **Purpose and logic:** Inserts the distinct normalized labels from the supplied array for an existing answer row on an active attempt.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id, $3: question_id, $4: selected_options text[]`
- **Tables:** `cutoff.answer_options`, `cutoff.answers`, `cutoff.attempts`
- **Source:** [`04_queries.sql` line 729](04_queries.sql#L729)

## W6 — Submit an owned active attempt

- **Operation:** WRITE
- **Purpose and logic:** Changes one owned active attempt to submitted and records its submission timestamp.
- **Parameters:** `$1: authenticated_user_id, $2: attempt_id`
- **Tables:** `cutoff.attempts`
- **Source:** [`04_queries.sql` line 744](04_queries.sql#L744)

## W7 — Close an expired active attempt before starting another

- **Operation:** WRITE
- **Purpose and logic:** Submits one active attempt only after the paper deadline has passed.
- **Parameters:** `$1: authenticated_user_id, $2: test_id`
- **Tables:** `cutoff.attempts`, `cutoff.tests`
- **Source:** [`04_queries.sql` line 755](04_queries.sql#L755)

## W8 — Create a taxonomy subject if it does not already exist

- **Operation:** WRITE
- **Purpose and logic:** Inserts a subject after trimming its canonical name; does nothing if that name already exists.
- **Parameters:** `$1: canonical subject name`
- **Tables:** `cutoff.subjects`
- **Source:** [`04_queries.sql` line 768](04_queries.sql#L768)

## W9 — Create a chapter within its subject

- **Operation:** WRITE
- **Purpose and logic:** Inserts a chapter under a subject after trimming its name; does nothing if the subject/name pair already exists.
- **Parameters:** `$1: subject_id, $2: canonical chapter name`
- **Tables:** `cutoff.chapters`
- **Source:** [`04_queries.sql` line 778](04_queries.sql#L778)

## W10 — Create a topic within its chapter

- **Operation:** WRITE
- **Purpose and logic:** Inserts a topic under a chapter after trimming its name; does nothing if the chapter/name pair already exists.
- **Parameters:** `$1: chapter_id, $2: canonical topic name`
- **Tables:** `cutoff.topics`
- **Source:** [`04_queries.sql` line 787](04_queries.sql#L787)

## W11 — Create a new verified question/version

- **Operation:** WRITE
- **Purpose and logic:** Creates a question version with its chapter, text, type, difficulty and optional explanation.
- **Parameters:** `$1: chapter_id, $2: question text, $3: question type, $4: difficulty, $5: explanation or NULL`
- **Tables:** `cutoff.questions`
- **Source:** [`04_queries.sql` line 796](04_queries.sql#L796)

## W12 — Assign the new question its optional primary topic

- **Operation:** WRITE
- **Purpose and logic:** Assigns a question its primary topic.
- **Parameters:** `$1: new_question_id, $2: topic_id`
- **Tables:** `cutoff.question_topics`
- **Source:** [`04_queries.sql` line 805](04_queries.sql#L805)

## W13 — Add one option to a new choice question

- **Operation:** WRITE
- **Purpose and logic:** Adds one normalized option label and option text to a question.
- **Parameters:** `$1: new_question_id, $2: option label, $3: option text`
- **Tables:** `cutoff.question_options`
- **Source:** [`04_queries.sql` line 813](04_queries.sql#L813)

## W14 — Record a correct option for a new choice question

- **Operation:** WRITE
- **Purpose and logic:** Records one normalized correct-option label for a choice question.
- **Parameters:** `$1: new_question_id, $2: correct option label`
- **Tables:** `cutoff.correct_options`
- **Source:** [`04_queries.sql` line 822](04_queries.sql#L822)

## W15 — Record an inclusive numerical answer range

- **Operation:** WRITE
- **Purpose and logic:** Stores an inclusive accepted numerical answer range.
- **Parameters:** `$1: new_question_id, $2: accepted_min, $3: accepted_max`
- **Tables:** `cutoff.numerical_keys`
- **Source:** [`04_queries.sql` line 831](04_queries.sql#L831)

## W16 — Add an ordered image to a new question

- **Operation:** WRITE
- **Purpose and logic:** Adds an image at a specified position for a question.
- **Parameters:** `$1: new_question_id, $2: image position, $3: image URL`
- **Tables:** `cutoff.question_images`
- **Source:** [`04_queries.sql` line 841](04_queries.sql#L841)

## W17 — Add an ordered image to a new option

- **Operation:** WRITE
- **Purpose and logic:** Adds an image at a specified position for a choice option.
- **Parameters:** `$1: new_question_id, $2: option label, $3: image position, $4: image URL`
- **Tables:** `cutoff.option_images`
- **Source:** [`04_queries.sql` line 850](04_queries.sql#L850)

## W18 — Create a new historical paper/version

- **Operation:** WRITE
- **Purpose and logic:** Creates a historical paper/version with its title, year, session and duration.
- **Parameters:** `$1: title, $2: exam year, $3: session label, $4: duration minutes`
- **Tables:** `cutoff.tests`
- **Source:** [`04_queries.sql` line 859](04_queries.sql#L859)

## W19 — Place a verified question in the new paper with its marking rules

- **Operation:** WRITE
- **Purpose and logic:** Places a question in a paper at a position with the paper-specific correct, incorrect and unattempted marks.
- **Parameters:** `$1: new_test_id, $2: question_id, $3: position, $4: correct marks, $5: incorrect marks, $6: unattempted marks`
- **Tables:** `cutoff.test_questions`
- **Source:** [`04_queries.sql` line 869](04_queries.sql#L869)
