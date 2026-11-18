# Cutoff — AP + DE Database Project

Cutoff is a JEE Main practice platform. Students select a previous-year paper,
attempt its questions, submit their answers, and review their scores, accuracy,
time spent, and performance by subject, chapter, and topic.

This repository contains the **database coursework for Cutoff**. The application
is being developed separately in [KrishnaGulalia/cutoff](https://github.com/KrishnaGulalia/cutoff).
The MakeMyTrip assignment belongs in the separate DE repository.

## Start here

Read **[CP1: Database normalization](dbms/01_normalization.md)**.
It explains the data, shows the problems with one large table, and takes the
design through **1NF → 2NF → 3NF**, with a BCNF check at the end.

For CP2, open the [zoomable ER diagram](dbms/02_er_diagram.svg) or the
[PostgreSQL schema](dbms/03_schema.sql).
The diagram groups tables into classification, question bank, papers, and student
activity, with column types, key markers, nullable fields, and crow's-foot cardinalities.
The [editable Draw.io source](dbms/02_er_diagram.drawio) is included.
The [diagram guide and Mermaid version](dbms/02_er_diagram.md) also show the
relationships with labels such as “starts”, “contains”, and “records”.

**[CP3: Application queries](dbms/04_queries.sql)** defines the SQL for Cutoff's
student workflows and question imports using the finalized database schema.

![Cutoff database ER diagram](dbms/02_er_diagram.svg)

The design supports:

- Student accounts and login.
- Historical papers and reusable questions.
- Single-choice, multiple-select, and numerical answers.
- Multiple attempts by the same student on the same paper.
- Saving answers, marking questions for review, and tracking time.
- Server-side scoring and subject/chapter/topic analysis.

## How the database fits the application

```text
React interface → Express backend → Prisma ORM → PostgreSQL
```

The backend manages authentication, saves attempts, and calculates results.
Correct answers are excluded from question-delivery responses during a test.

CP1 defines the relational model, its business rules, keys, dependencies, and
integrity constraints. It ends with plain-language explanations of the main
design choices. The same model forms the basis of the ER diagram and SQL schema.

## AP checkpoint progress

| Checkpoint | Due date (2026) | Required file | Current content |
|---|---|---|---|
| CP1 | 16 November | `dbms/01_normalization.md` | Written: tables, keys, dependencies, 1NF, 2NF, 3NF, and BCNF discussion |
| CP2 | 17 November | `dbms/02_er_diagram.*`, `dbms/03_schema.sql` | Written and validated: ER diagram, all 16 tables, keys, constraints, and response guards |
| CP3 | 19 November | `dbms/04_queries.sql` | Written and validated: 18 READ queries and 19 WRITE queries |
| CP4 | 23 November | `dbms/05_query_timings.md`, `dbms/plans/` | Timing file is empty; plans have not been added |

The tracker checks files with real content on the repository's **default branch**.
Writing a file locally does not submit it. Every team member must also have their
own commits. The table above describes the files, not a confirmed tracker result.

## Repository contents

```text
CutOff_AP_2026/
├── README.md
└── dbms/
    ├── 01_normalization.md    # CP1: Cutoff database design
    ├── 02_er_diagram.svg      # CP2: zoomable diagram
    ├── 02_er_diagram.png      # CP2: high-resolution image
    ├── 02_er_diagram.drawio   # Editable source for the main SVG/PNG diagram
    ├── 02_er_diagram.md       # Diagram guide and Mermaid with named relationships
    ├── 02_er_diagram.mmd      # Editable Mermaid source
    ├── 03_schema.sql          # CP2: PostgreSQL DDL and integrity triggers
    ├── 04_queries.sql         # CP3: parameterized application queries
    └── 05_query_timings.md    # CP4: query measurements
```

## CP3 query index

Each query has a stable ID, a `READ` or `WRITE` label, and a comment listing its
parameters in order. Every table reference uses the `cutoff` schema.

| IDs | Purpose |
|---|---|
| R1–R2 | Login/duplicate-email lookup and student profile |
| R3–R4 | Paper catalogue, filters, pagination, and subject-wise paper details |
| R5–R7 | Question delivery, options, and images without answer keys |
| R8–R10 | Resume an attempt, read the timer, and restore saved answers/review flags |
| R11 | Question-level evaluation and review after submission |
| R12 | Score, correct/incorrect/skipped counts, accuracy, and time totals |
| R13 | Subject, chapter, topic, difficulty, and time analysis |
| R14 | Student attempt history with submitted result summaries |
| R15–R16 | Taxonomy lookup and new-paper import validation |
| R17 | Lock an owned active attempt during an answer-save or submission transaction |
| R18 | Database health check |
| W1 | Register a student with a password hash |
| W2–W7 | Start, save, replace/clear selections, submit, and close expired attempts |
| W8–W10 | Create shared subjects, chapters, and topics |
| W11–W17 | Import new questions, topic assignments, options, keys, and images |
| W18–W19 | Create a new paper and map its questions with paper-specific marks |

R17 is a read query that **takes a row lock**. It is used inside a transaction,
not as an ordinary page-fetch query. Import operations are for the trusted backend
and must not be exposed as student actions.

## Running the queries

First apply `dbms/03_schema.sql` to a fresh development database. Then, from the
repository root, open a PostgreSQL session:

```bash
psql -X -v ON_ERROR_STOP=1 -d cutoff_dev
```

Inside that same session:

```sql
\i dbms/04_queries.sql

-- List up to 20 papers without filtering by year, session, or title.
EXECUTE cutoff_r3(NULL, NULL, NULL, 20, 0);

-- Check the database connection.
EXECUTE cutoff_r18;
```

The file uses `PREPARE` to give each parameterized statement a reusable name.
Loading it registers the statements; it does not execute the writes. `EXECUTE`
supplies values for `$1`, `$2`, and the remaining parameters. The prepared names
exist only in the connection that loaded the file. Reconnect before loading it
again. Application code can use the statement bodies with its driver's bound
parameters.

## Important query behavior

- **Student ownership:** attempt queries use the authenticated user's ID. Result
  queries return evaluation only after that user's attempt is submitted.
- **Answer saving:** run R17 → W3 → W4 → W5 inside one transaction. R17 must return
  the owned active attempt and W3 must return the saved row. Roll back the entire
  transaction on an error. Numerical answers omit W5. This keeps answer state and
  selected options together when replacing or clearing a response.
- **Time tracking:** W3 accepts the cumulative time spent on that question.
  Repeating a save does not count the same elapsed time twice.
- **Scoring:** multiple-select answers require an exact set match; numerical
  answers use inclusive bounds. A numeric zero is a valid response. Unanswered
  questions remain in the result through left joins.
- **Accuracy and invalid keys:** accuracy is `NULL` when nothing was attempted
  (display “N/A”). An invalid answer key is reported explicitly and prevents a
  misleading total score from being returned.
- **Imports:** create the new paper and its content in one transaction, run R16,
  and commit only when it returns no issues and deferred constraints pass. Used
  questions and papers retain their content and marking rules; corrections use
  new IDs. The full transaction sequences are at the top of the query file.


For CP4, time the prepared statements with
`EXPLAIN (ANALYZE, BUFFERS) EXECUTE ...`. Use real fixture parameters, repeat each
query three times, and report the average. Run writes and their required setup
inside a transaction and roll back after each run. Query timings are not yet
recorded in this repository.

## Understanding the SQL

Start with R2 (one student), R5 (joining questions to their paper), and W1
(inserting a student). Then read R11's scoring steps before R12–R14, which
summarize those results. Table aliases use names such as `paper`, `question`,
and `answer` so the source of each column is clear.

For example, the query inside R2 is an ordinary `SELECT`:

```sql
SELECT user_id, user_name, email, user_created_at, user_updated_at
FROM cutoff.users
WHERE user_id = $1;
```

`$1` means “the first input value.” `EXECUTE cutoff_r2(7);` runs this query
with `user_id = 7`. `PREPARE cutoff_r2(BIGINT) AS` gives the query its name
and declares that input as an integer ID. Every query lists its inputs explicitly.

| Syntax | Meaning in this project |
|---|---|
| `JOIN ... ON ...` | Combine related rows using their IDs. |
| `LEFT JOIN` | Keep the question even when it has no saved answer or topic. |
| `CASE WHEN ... THEN ... ELSE ... END` | Choose a value using a condition, like if/else. |
| `COUNT(CASE WHEN outcome = 'correct' THEN 1 END)` | Count only correct answers. Other rows produce `NULL`, which `COUNT` ignores. |
| `COALESCE(value, 0)` | Use zero when the value is missing. |
| `NULLIF(value, 0)` | Return `NULL` when the value is zero, preventing division by zero in accuracy. |
| `WITH name AS (...)` | Name an intermediate result for this query; it does not create a stored table. |
| `UNION ALL` | Combine report rows, retaining every row. R13 builds separate subject, chapter, topic and difficulty groups. |
| `ARRAY(...)` / `cardinality(...)` | Collect option labels into a list / count the labels in that list. |
| `ON CONFLICT ... DO UPDATE` | Insert a new answer, or update it if the same answer already exists. |
| `RETURNING` | Return the row's requested values after a write, such as its generated ID. |

Scoring follows four steps: **find the submitted attempt → collect questions,
responses and keys → decide each outcome → assign marks**. R11 returns those
question rows. R12 totals them, R13 groups them, and R14 attaches totals to the
student's attempt history. Each query includes the steps so it can run independently.

For saving an answer, `BEGIN` starts a transaction, `COMMIT` keeps all its changes,
and `ROLLBACK` cancels them. R17's `FOR UPDATE` locks the attempt until that
transaction ends, so submission waits for an ongoing answer save to finish.
The required save sequence is R17 → W3 → W4 → W5; skip W5 for numerical answers.
