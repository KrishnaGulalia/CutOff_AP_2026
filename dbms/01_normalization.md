# CP1: Normalization of the Cutoff Database

## 1. Overview

Cutoff lets a student attempt a historical JEE Main paper and analyse the result.
We need to store students, papers, questions, answer keys, attempts, and responses.
The same student can attempt a paper more than once, and the same question can
appear in more than one paper.

This document takes that data through **1NF → 2NF → 3NF**, then checks BCNF.
Each stage lists its tables and functional dependencies.

This document defines the relational database design for the **Cutoff AP project**.
The scope covers accounts, paper selection, question delivery, saved responses,
submission, scoring, and performance analysis.

### Scope and decisions

| Rule | What it means for our database |
|---|---|
| Each student has one account with a unique email | Email is an alternate key of `users`; store a password hash, not the password |
| One test represents one paper/version | A test has a title, year, session label, and duration; titles are not assumed unique |
| A question can appear in several tests | Use a separate `test_questions` table |
| A question appears at most once in a particular test | `(test_id, question_id)` is unique |
| Position is unique within the whole test | `(test_id, position)` is also unique; numbering does not restart for each subject |
| Marks belong to the question's placement in a test | Store marks in `test_questions`, not `questions` |
| A student can attempt the same test repeatedly | Give every attempt a separate `attempt_id`; do not make `(user_id, test_id)` unique |
| An attempt has at most one current response per question | The response key is `(attempt_id, question_id)` |
| A question has one primary chapter and optionally one primary topic | A chapter belongs to one subject; a topic belongs to one chapter |
| Some chapter/topic names may repeat under different parents | Names are unique within their parent, not globally |
| Options, selected options, and images can repeat | Store each item as a separate row, not a comma-separated list |
| Published question content and marking rules must remain stable once used | Corrections affecting scoring require a new question/test version, represented by new IDs |

The MVP includes `SINGLE_CHOICE`, `MULTIPLE_SELECT`, and `NUMERICAL` questions.
Multiple-select scoring uses an exact set match, with no partial credit. A paper's
marking values are stored explicitly; they are not inferred from difficulty or
question type. Tags, multiple topic classifications, verification history, and
recommendation models are outside this CP1 scope.

### Notation

- **PK**: primary key, which uniquely identifies a row.
- **FK**: foreign key, which refers to an existing row in another table.
- **CK**: candidate key, a minimal set of columns that uniquely identifies a row.
- **FD**: functional dependency. `X → Y` means one value of X determines exactly
  one value of Y. For example, `user_id → user_name, email`.
- A **partial dependency** is a dependency on only part of a composite candidate key.
- A **transitive dependency** is a chain such as
  `question_id → chapter_id → chapter_name`.

Dependencies describe business rules, not coincidences in a small sample.
For example, `question_id → marks_correct` is false because different tests may
award different marks for the same question.

## 2. Starting point: unnormalized data (UNF)

Imagine saving a whole attempt in one nested record:

```text
AttemptRecord {
  attempt_id, user_id, user_name, email, password_hash,
  test_id, test_title, exam_year, session_label, duration_minutes,
  started_at, submitted_at, attempt_status,
  questions: [
    {
      question_id, position, question_text, question_type, difficulty,
      subject_id, subject_name, chapter_id, chapter_name,
      topic_id, topic_name, explanation_text,
      marks_correct, marks_incorrect, marks_unattempted,
      options: [{option_label, option_text, images: [...]}],
      question_images: [...], correct_options: [...],
      accepted_min, accepted_max,
      selected_options: [...], numerical_response,
      marked_for_review, time_spent_seconds
    }
  ]
}
```

The `questions`, `options`, and image/answer lists are repeating groups. A plain
text question or explanation is one content value; an independently addressable
list of options is a collection of facts.

### Problems with this structure

- **Update anomaly:** changing a student's name requires changing every copied
  attempt record. Changing a chapter name requires changing every copied question.
- **Insertion anomaly:** a design centred only on attempt records cannot store an
  unused paper or a new question independently.
- **Deletion anomaly:** deleting the last attempt could remove the only stored
  copy of a question or paper.
- **Repeated facts:** the same paper title and correct options are copied for
  every student, even though they do not depend on the student.

The following example uses invented IDs and responses only to explain the design.
It is not imported exam data.

| Attempt | Student | Test | Question | Position | Chapter | Options | Selected options |
|---|---|---|---|---:|---|---|---|
| A101 | U7 / Riya | T1 / Practice paper | Q10 | 1 | Mechanics | A, B, C, D | B |
| A101 | U7 / Riya | T1 / Practice paper | Q11 | 2 | Mechanics | A, B, C, D | A, C |
| A102 | U7 / Riya | T1 / Practice paper | Q10 | 1 | Mechanics | A, B, C, D | D |

`A101` and `A102` must remain separate even though the student and test are the same.

## 3. First Normal Form (1NF): remove repeating groups

**Rule:** each row is identifiable, and each attribute holds one value from its
domain. For this relational design, options, selections, and images become rows.
We do not hide those relationships inside JSON or comma-separated strings.

JSON is useful for API transport and is a valid PostgreSQL type. Its presence
alone does not prove a database is badly designed; here we explicitly model the
facts inside it so keys and relationships can be checked.

### 3.1 Main 1NF table

One row in `attempt_question_1nf` represents one question in one attempt,
including an unanswered question.

```text
attempt_question_1nf(
  attempt_id, question_id,
  user_id, user_name, email, password_hash, user_created_at, user_updated_at,
  test_id, test_title, exam_year, session_label, duration_minutes, test_created_at,
  started_at, submitted_at, attempt_status,
  question_text, question_type, difficulty, explanation_text, question_created_at,
  chapter_id, chapter_name, subject_id, subject_name,
  position, marks_correct, marks_incorrect, marks_unattempted,
  numerical_response, marked_for_review, time_spent_seconds, answer_updated_at
)
```

**PK:** `(attempt_id, question_id)`.
**Other CK:** `(attempt_id, position)`, because positions are unique within a test
and an attempt identifies its test.

The relevant FDs are:

```text
attempt_id → user_id, test_id, started_at, submitted_at, attempt_status
user_id → user_name, email, password_hash, user_created_at, user_updated_at
email → user_id
test_id → test_title, exam_year, session_label, duration_minutes, test_created_at
question_id → question_text, question_type, difficulty, explanation_text,
              question_created_at, chapter_id
chapter_id → chapter_name, subject_id
subject_id → subject_name
subject_name → subject_id
(subject_id, chapter_name) → chapter_id
(test_id, question_id) → position, marks_correct, marks_incorrect, marks_unattempted
(test_id, position) → question_id, marks_correct, marks_incorrect, marks_unattempted
(attempt_id, question_id) → numerical_response, marked_for_review,
                            time_spent_seconds, answer_updated_at
```

For example, A101 fixes the student and test regardless of which question row we
read. Q10 fixes its text regardless of which student attempted it. This table is
in 1NF, but it still mixes facts with different determinants.

### 3.2 Separate 1NF tables for collections and optional topic data

`question_topics_1nf` has a row only when a topic is assigned. Its chapter column
is called `topic_chapter_id` below to distinguish it from the question's chapter.

| Table and attributes | PK | Nontrivial FDs |
|---|---|---|
| `question_topics_1nf(question_id, topic_id, topic_name, topic_chapter_id)` | `question_id` | `question_id → topic_id`; `topic_id → topic_name, topic_chapter_id`; `(topic_chapter_id, topic_name) → topic_id` |
| `question_options(question_id, option_label, option_text)` | `(question_id, option_label)` | `(question_id, option_label) → option_text` |
| `correct_options(question_id, option_label)` | `(question_id, option_label)` | None beyond dependencies on the whole key; both attributes form the key |
| `numerical_keys(question_id, accepted_min, accepted_max)` | `question_id` | `question_id → accepted_min, accepted_max` |
| `answer_options(attempt_id, question_id, option_label)` | `(attempt_id, question_id, option_label)` | No non-key attributes |
| `question_images(question_id, image_position, image_url)` | `(question_id, image_position)` | `(question_id, image_position) → image_url` |
| `option_images(question_id, option_label, image_position, image_url)` | `(question_id, option_label, image_position)` | `(question_id, option_label, image_position) → image_url` |

An image URL is one scalar reference. `image_position` preserves display order.
An option label such as A is unique only within its question. We use no placeholder
option for numerical questions and no selection row for an unanswered question.

For the example's multiple-select response, store:

| attempt_id | question_id | option_label |
|---|---|---|
| A101 | Q11 | A |
| A101 | Q11 | C |

We do not combine options, question images, and selected options into one table:
that would multiply unrelated rows and repeat the same selection for each image.

## 4. Second Normal Form (2NF): remove partial dependencies

**Rule:** a relation must be in 1NF, and every non-prime attribute must depend on
the whole of every candidate key, not just a proper subset of a key.

In `attempt_question_1nf`, the main key is `(attempt_id, question_id)`:

- Student and attempt details depend on `attempt_id` alone.
- Question content and classification depend on `question_id` alone.
- A response and its time spent depend on both `attempt_id` and `question_id`.
- Paper position and marks describe `(test_id, question_id)`; they are shared by
  all attempts on that paper and are extracted into their own mapping table.

### 4.1 Tables after the 2NF decomposition

```text
attempts_2nf(
  attempt_id,
  user_id, user_name, email, password_hash, user_created_at, user_updated_at,
  test_id, test_title, exam_year, session_label, duration_minutes, test_created_at,
  started_at, submitted_at, attempt_status
)

questions_2nf(
  question_id, question_text, question_type, difficulty, explanation_text,
  question_created_at, chapter_id, chapter_name, subject_id, subject_name
)

test_questions(
  test_id, question_id, position,
  marks_correct, marks_incorrect, marks_unattempted
)

answers(
  attempt_id, question_id, numerical_response,
  marked_for_review, time_spent_seconds, answer_updated_at
)
```

The seven tables from section 3.2 also remain. They have no partial dependencies.
`question_topics_1nf` is now called `question_topics_2nf`; its transitive dependency
will be removed in the next step.

| Table | Candidate keys (first is PK) | FDs at this stage |
|---|---|---|
| `attempts_2nf` | `attempt_id` | `attempt_id →` every other attribute; `user_id →` user details; `email → user_id`; `test_id →` test details |
| `questions_2nf` | `question_id` | `question_id →` every other attribute; `chapter_id → chapter_name, subject_id`; `subject_id ↔ subject_name`; `(subject_id, chapter_name) → chapter_id` |
| `test_questions` | `(test_id, question_id)`; `(test_id, position)` | Each candidate key determines all remaining attributes |
| `answers` | `(attempt_id, question_id)` | Entire key determines response, review flag, time spent, and update time |
| `question_topics_2nf` | `question_id` | `question_id → topic_id`; `topic_id → topic_name, topic_chapter_id`; `(topic_chapter_id, topic_name) → topic_id` |
| Other six collection/key tables | As listed in section 3.2 | Unchanged from section 3.2 |

The single-column keys in `attempts_2nf` and `questions_2nf` cannot have partial
dependencies, but that does **not** make these tables 3NF. A student's name is
still repeated in every attempt, and a chapter's name in every question.

For example, if Q10 is worth 4 marks in T1 and 2 marks in T2, the two rows belong
in `test_questions`. Updating Q10's text should not change either marking rule.

## 5. Third Normal Form (3NF): remove transitive dependencies

**Rule:** for every nontrivial FD `X → A`, either X is a superkey or A is a prime
attribute (part of some candidate key). In our tables, the practical change is to
stop storing descriptive facts about one entity in another entity's row.

### 5.1 Dependencies we remove

| Dependency chain in 2NF | Problem | Decomposition |
|---|---|---|
| `attempt_id → user_id → user_name, email, password_hash, ...` | User details repeat for every attempt | `users` and `attempts` |
| `attempt_id → test_id → test_title, duration_minutes, ...` | Test details repeat for every attempt | `tests` and `attempts` |
| `question_id → chapter_id → chapter_name, subject_id` | Chapter facts repeat for every question | `chapters` and `questions` |
| `chapter_id → subject_id → subject_name` | Subject name repeats for every chapter/question | `subjects` and `chapters` |
| `question_id → topic_id → topic_name, topic_chapter_id` | Topic facts repeat for every classified question | `topics` and `question_topics` |

`questions` keeps its chapter because topic classification is optional.
`question_topics` records the optional topic without copying the topic name or
chapter into the question row. The assigned topic must belong to the question's
chapter; this is an additional consistency rule described in section 7.

### 5.2 Final tables: attributes and keys

These are the final 3NF relations to use for the CP2 ER diagram and SQL schema.
Table and column names use SQL-style `snake_case`.
All listed candidate-key columns must be non-null.

| Table | Attributes | PK | Other candidate keys |
|---|---|---|---|
| `users` | `user_id, user_name, email, password_hash, user_created_at, user_updated_at` | `user_id` | `email` |
| `tests` | `test_id, test_title, exam_year, session_label, duration_minutes, test_created_at` | `test_id` | None assumed |
| `subjects` | `subject_id, subject_name` | `subject_id` | `subject_name` |
| `chapters` | `chapter_id, subject_id, chapter_name` | `chapter_id` | `(subject_id, chapter_name)` |
| `topics` | `topic_id, chapter_id, topic_name` | `topic_id` | `(chapter_id, topic_name)` |
| `questions` | `question_id, chapter_id, question_text, question_type, difficulty, explanation_text, question_created_at` | `question_id` | None assumed |
| `question_topics` | `question_id, topic_id` | `question_id` | None assumed |
| `question_options` | `question_id, option_label, option_text` | `(question_id, option_label)` | None assumed |
| `correct_options` | `question_id, option_label` | `(question_id, option_label)` | None assumed |
| `numerical_keys` | `question_id, accepted_min, accepted_max` | `question_id` | None assumed |
| `question_images` | `question_id, image_position, image_url` | `(question_id, image_position)` | None assumed |
| `option_images` | `question_id, option_label, image_position, image_url` | `(question_id, option_label, image_position)` | None assumed |
| `test_questions` | `test_id, question_id, position, marks_correct, marks_incorrect, marks_unattempted` | `(test_id, question_id)` | `(test_id, position)` |
| `attempts` | `attempt_id, user_id, test_id, started_at, submitted_at, attempt_status` | `attempt_id` | None assumed |
| `answers` | `attempt_id, question_id, numerical_response, marked_for_review, time_spent_seconds, answer_updated_at` | `(attempt_id, question_id)` | None assumed |
| `answer_options` | `attempt_id, question_id, option_label` | `(attempt_id, question_id, option_label)` | None assumed |

Names and emails are canonicalised consistently before storage. Emails are
trimmed/lowercased and unique under that policy. Taxonomy names use one agreed
spelling and case per parent. Password hashes are never used as identifying keys.

### 5.3 Functional dependencies in the final tables

In the table below, “remaining attributes” means every attribute listed in
section 5.2 except the determinant itself. These are the generating FDs; implied
dependencies follow from them.

| Relation | Functional dependencies |
|---|---|
| `users` | `user_id →` remaining attributes; `email →` remaining attributes |
| `tests` | `test_id →` remaining attributes |
| `subjects` | `subject_id → subject_name`; `subject_name → subject_id` |
| `chapters` | `chapter_id → subject_id, chapter_name`; `(subject_id, chapter_name) → chapter_id` |
| `topics` | `topic_id → chapter_id, topic_name`; `(chapter_id, topic_name) → topic_id` |
| `questions` | `question_id →` remaining attributes |
| `question_topics` | `question_id → topic_id` |
| `question_options` | `(question_id, option_label) → option_text` |
| `correct_options` | No nontrivial FDs; both attributes form the key |
| `numerical_keys` | `question_id → accepted_min, accepted_max` |
| `question_images` | `(question_id, image_position) → image_url` |
| `option_images` | `(question_id, option_label, image_position) → image_url` |
| `test_questions` | `(test_id, question_id) → position, marks_correct, marks_incorrect, marks_unattempted`; `(test_id, position) → question_id, marks_correct, marks_incorrect, marks_unattempted` |
| `attempts` | `attempt_id →` remaining attributes |
| `answers` | `(attempt_id, question_id) → numerical_response, marked_for_review, time_spent_seconds, answer_updated_at` |
| `answer_options` | No nontrivial FDs; all three attributes form the key |

There is no rule `topic_id → question_id`: many questions may share a topic.
There is also no rule `question_type → marks_correct`: marks belong to the paper
mapping, even if the initial data happens to use the same values everywhere.

### 5.4 Foreign keys and relationships

| Child relation | Foreign key reference | Meaning |
|---|---|---|
| `chapters` | `subject_id → subjects.subject_id` | One subject has many chapters |
| `topics` | `chapter_id → chapters.chapter_id` | One chapter has many topics |
| `questions` | `chapter_id → chapters.chapter_id` | One chapter classifies many questions |
| `question_topics` | `question_id → questions.question_id`; `topic_id → topics.topic_id` | Each question has zero or one topic; each topic can classify many questions |
| `question_options` | `question_id → questions.question_id` | A choice question has multiple options |
| `correct_options` | `(question_id, option_label) → question_options` | Every correct option exists for that question |
| `numerical_keys` | `question_id → questions.question_id` | A numerical question has one accepted interval |
| `question_images` | `question_id → questions.question_id` | A question has zero or more ordered images |
| `option_images` | `(question_id, option_label) → question_options` | An option has zero or more ordered images |
| `test_questions` | `test_id → tests.test_id`; `question_id → questions.question_id` | Resolves the many-to-many test/question relationship |
| `attempts` | `user_id → users.user_id`; `test_id → tests.test_id` | Each attempt belongs to one student and one test |
| `answers` | `attempt_id → attempts.attempt_id`; `question_id → questions.question_id` | Stores the state of a question in one attempt |
| `answer_options` | `(attempt_id, question_id) → answers`; `(question_id, option_label) → question_options` | Every selected option belongs to the question being answered |

The main route through the data is:

```text
users → attempts → answers → answer_options
           ↓          ↓             ↓
         tests → test_questions → questions → question_options
                                    ↓
                                 chapters → subjects

questions → question_topics → topics → chapters
```

Arrows above indicate navigation, not cardinality; the table defines the keys
and relationships precisely.

### 5.5 How an attempt is represented

For attempt A101 on test T1:

1. `attempts` stores U7, T1, start time, submission time, and status once.
2. `test_questions` supplies the paper's questions, their positions, and marks.
3. `answers` stores one row per question whose state has been saved. A saved row
   can have no response while still recording time spent or a review flag.
4. For a single-choice answer, `answer_options` contains one selected option.
   For multiple-select it contains one row per selected option.
5. For a numerical answer, `answers.numerical_response` contains one number and
   there are no `answer_options` rows for that answer.
6. Questions with no saved answer are found by a left join from the test's
   question list. They count as unattempted; they must not disappear from results.

Starting attempt A102 creates new answer rows under A102. It never overwrites A101.

### 5.6 Required values, defaults, and deletion rules

All columns are required (`NOT NULL`) except the following:

| Nullable column | Meaning of `NULL` |
|---|---|
| `questions.explanation_text` | An explanation has not been provided |
| `attempts.submitted_at` | The attempt is still in progress |
| `answers.numerical_response` | No numerical response is present; choice responses are stored in `answer_options` |

An optional topic is represented by **no row** in `question_topics`, not a row
with a null key. The same approach applies to missing images and selections.
Every historical test has an `exam_year` and a `session_label`; the label identifies
the exam session/shift in readable form. Neither the title nor the session label
is assumed to uniquely identify a paper.

| Attribute or group | Domain or default |
|---|---|
| `question_type` | `SINGLE_CHOICE`, `MULTIPLE_SELECT`, or `NUMERICAL` |
| `difficulty` | `easy`, `medium`, or `hard` |
| `attempt_status` | `IN_PROGRESS` by default; changes to `SUBMITTED` on submission |
| `marked_for_review` | `false` by default |
| `time_spent_seconds` | Integer, default `0`, never negative |
| Positions and duration | Positive integers |
| Marks and numerical values | Exact decimal values (`NUMERIC`), rather than floating-point values |
| Timestamps | Time-zone-aware timestamps; creation/start/update times are recorded when the corresponding event occurs |

For `SINGLE_CHOICE` and `MULTIPLE_SELECT`, `numerical_response` stays null. For
`NUMERICAL`, the response is stored there and there are no selected-option rows.
A numerical response of **0 is a valid answer**, not an unanswered question.

Use `ON DELETE RESTRICT` for the foreign keys in section 5.4. This prevents
accidental deletion of students, papers, questions, or options that still have
related records. An intentional removal requires deleting dependent rows in an
explicit transaction. Published content referenced by attempts is retained;
deletion rules and the immutability rule in section 7 protect that history.

## 6. BCNF check

**BCNF requires every determinant in a nontrivial FD to be a superkey.**

Under the stated business rules, all final relations in section 5.2 satisfy BCNF:

- In `users`, both determinants (`user_id` and `email`) are candidate keys.
- In `subjects`, `chapters`, and `topics`, each ID and the stated unique name
  combination is a candidate key.
- In `test_questions`, both `(test_id, question_id)` and `(test_id, position)`
  are candidate keys.
- In `questions`, `tests`, `attempts`, `question_topics`, and `numerical_keys`,
  every nontrivial FD has the relation's primary key as its determinant.
- In the option, image, and answer tables, non-key attributes depend on the
  entire composite key.
- `correct_options` and `answer_options` contain only key attributes and have
  no nontrivial FDs under these rules.

The BCNF result follows from the business rules and dependencies stated in this
document. Foreign keys and the cross-table checks below enforce the additional
relationships between these tables.

## 7. Integrity rules beyond normalization

Normal forms remove certain kinds of repetition. They do not ensure that a
response is valid or that an attempt was scored correctly.

| Rule | Enforcement |
|---|---|
| IDs, email, positions, and mapping pairs are unique | Primary keys and the unique constraints listed above |
| Referenced rows exist | Foreign keys listed in section 5.4 |
| A response is for a question in the attempt's test | Check the join `answers → attempts → test_questions` in a database trigger or transactional backend operation; the two basic answer FKs alone do not enforce this |
| A question's optional topic belongs to its chapter | Check `questions.chapter_id = topics.chapter_id` on assignment and on relevant parent changes; use a trigger or coordinated transactional validation |
| Single-choice keys/responses have one option; multiple-select has one or more | Validate question type and row counts on publication/submission; an empty response is allowed while taking the test |
| Numerical questions have a numerical key and no choice options/responses | Validate subtype consistency; use `NUMERIC` values and `accepted_min <= accepted_max` |
| Numerical correctness has one rule | Accept a response inside the inclusive stored interval; for an exact answer use equal bounds; encode any intended tolerance in those bounds |
| Durations and positions are positive; time spent is nonnegative | `CHECK` constraints |
| Mark values have a consistent sign | Store signed awards: normally `marks_correct > 0`, `marks_incorrect <= 0`, `marks_unattempted = 0`; for example 4, -1, 0 |
| Status is valid and submission time follows start time | Allowed-status and timestamp checks; submitted attempts require `submitted_at` |
| Submitted attempts cannot be edited | Enforce the state transition and answer writes transactionally, with locking/checks against concurrent submission |
| A student has at most one active attempt per test | A partial unique index for `IN_PROGRESS`; it must still permit multiple submitted attempts |
| Past results stay reproducible | Freeze referenced content, keys, mappings, and marks after use; restrict deletion of referenced records; changes requiring a new version get new IDs |

Keep answer keys out of the test-delivery API projection. A normalized schema
does not itself prevent the backend from accidentally sending them to the client.

## 8. Scores and analytics

The normalized base tables store responses and marking rules. They do not need
separate copies of a student's name, paper title, subject name, or total score in
every answer.

For each question in the attempt's paper:

```text
no response       → marks_unattempted
correct response  → marks_correct
incorrect response → marks_incorrect

attempt score = sum of question marks
attempted count = correct count + incorrect count
accuracy (%) = 100 × correct count / attempted count
```

When `attempted count = 0`, show accuracy as “N/A” rather than divide by zero.
Time totals are calculated from `answers.time_spent_seconds`. Subject/chapter
analytics join through `questions → chapters → subjects`; topic analytics join
through `question_topics → topics`. Questions without a topic should appear in
an “Unclassified topic” group instead of being silently excluded.

Scores, correctness, result counts, and accuracy are derived from saved responses,
answer keys, and the paper's marking rules. They are calculated for result views
rather than stored as additional base facts. This avoids maintaining duplicate
results when the source data changes. Preserving the question and paper version
used by each attempt keeps historical results reproducible.

Derived values are not automatically a violation of 3NF: the normal form depends
on functional dependencies within a relation. The decision here is to keep one
source for scoring facts and calculate the results from it.

## 9. Why the decomposition preserves the data

The splits follow the determinants of the facts:

- Splitting users out of `attempts_2nf` shares `user_id`, a key of `users`.
  Joining on that key restores exactly one user's details for an attempt.
- Splitting tests out of `attempts_2nf` shares `test_id`, a key of `tests`.
- Splitting chapters and subjects out of `questions_2nf` shares keys of their
  new tables. A question still reaches its chapter and subject without copying names.
- Splitting topics out of `question_topics_2nf` shares `topic_id`, a key of `topics`.
- The first wide table can be reconstructed from `answers`, `attempts`,
  `questions`, `test_questions`, and the descriptive tables using their keys.
  During the conceptual decomposition, retain an answer-state row for every
  original `(attempt_id, question_id)` pair. Each join matches one corresponding row.

These key-based decompositions are lossless for the original relation. Independent
collection tables retain all options/images/selections without forcing a Cartesian
product. In the running app, sparse answer storage is a separate choice: derive
unanswered question rows from the attempt's test and left join saved answers.
Optional topics likewise use a left join.

The generating FDs listed above are preserved in individual final tables and can
be enforced through their primary/unique keys. Rules such as “the question belongs
to the attempt's test” are inclusion constraints, not ordinary single-table FDs;
they need the additional checks in section 7.

## 10. Key design points

1. **A paper and an attempt are different things.** `tests` describes the paper;
   `attempts` records one student's attempt at it. A second attempt gets a new ID
   so it cannot overwrite the first attempt's answers.

2. **Question content and paper-specific marks are separate.** `questions` stores
   the reusable content. `test_questions` stores its position and marks in a
   particular paper. The same question can therefore be reused without copying
   its text or forcing every paper to use the same marks.

3. **A composite key identifies a fact using more than one column.** In `answers`,
   neither an attempt ID nor a question ID is enough on its own. Their pair
   identifies one saved answer. An additional option label identifies each
   selection in a multiple-select response.

4. **Normalization gives each fact one place to live.** Student details belong in
   `users`, paper details in `tests`, and chapter names in `chapters`. A name can
   be corrected once without updating every answer or attempt that refers to it.

5. **An unanswered question still belongs in the result.** Start with all
   questions in the attempt's paper and left join the saved answers. This keeps
   questions with no saved response in the skipped count and total question count.

6. **Keys prevent duplicates; validation enforces meaning.** A unique key prevents
   two saved answers for the same attempt/question pair. Foreign keys ensure that
   referenced rows exist. Additional checks ensure that the question belongs to
   the correct paper and that the response matches its question type.

7. **Marks are signed values and results are calculated.** A correct answer may
   add `4`, an incorrect answer add `-1`, and an unanswered question add `0`.
   Summing these values produces the score; correct and incorrect counts produce
   accuracy. No extra copy of those totals is required in the base tables.
