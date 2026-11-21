# CP4 Query Performance Analysis

## Method

- PostgreSQL 18.6 (Postgres.app) on the local server; database: `cutoff_cp4_bench_2026`, created separately from `cutoff`.
- Loaded the unchanged [`03_schema.sql`](03_schema.sql) and the unchanged prepared statements from [`04_queries.sql`](04_queries.sql).
- Fixture data: 20 students, 3 subjects, 6 chapters, 12 topics, 120 questions, 6 papers (20 questions each), and 33 attempts with saved response states.
- Ran every prepared query ID (R1–R18 and W1–W19) three times using `EXPLAIN (ANALYZE, BUFFERS) EXECUTE ...`; the parameter values targeted valid fixture rows and workflow states.
- Each write run used its own `BEGIN`/`ROLLBACK`. Required parent rows/options were created inside that same transaction where needed; no benchmark write was committed.
- Timings below are PostgreSQL's reported **Execution Time** in milliseconds, taken from the actual plans. Average is the arithmetic mean of the three runs, rounded to 0.001 ms.
- The supplied SQL was prepared once per psql session. Plans are text format and include actual rows, buffers, planning time, and trigger time where PostgreSQL reported them.

## READ timings

| ID | Query | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R1 | Find an account for login or duplicate-email checking | 0.015 | 0.005 | 0.004 | **0.008** |
| R2 | Read the signed-in student profile | 0.004 | 0.004 | 0.003 | **0.004** |
| R3 | Browse papers with optional filters and pagination | 0.134 | 0.058 | 0.050 | **0.081** |
| R4 | Read paper details and subject-wise question/mark counts | 0.122 | 0.054 | 0.054 | **0.077** |
| R5 | Deliver paper questions without answers or explanations | 0.085 | 0.070 | 0.096 | **0.084** |
| R6 | Deliver choice options and their ordered images | 0.195 | 0.111 | 0.114 | **0.140** |
| R7 | Deliver ordered question images | 0.019 | 0.015 | 0.014 | **0.016** |
| R8 | Find the current resumable attempt | 0.050 | 0.010 | 0.009 | **0.023** |
| R9 | Read an owned attempt and its timer | 0.014 | 0.011 | 0.010 | **0.012** |
| R10 | Restore question navigation, review flags and saved responses | 0.096 | 0.063 | 0.059 | **0.073** |
| R11 | Review and score every question in a submitted attempt | 1.301 | 1.565 | 1.353 | **1.406** |
| R12 | Calculate the result summary | 5.333 | 4.142 | 4.898 | **4.791** |
| R13 | Analyse subject, chapter, topic, difficulty and time usage | 1.540 | 1.571 | 1.512 | **1.541** |
| R14 | List a student's attempt history with submitted result summaries | 3.192 | 3.111 | 3.080 | **3.128** |
| R15 | Resolve the shared subject/chapter/topic taxonomy | 0.043 | 0.040 | 0.032 | **0.038** |
| R16 | Validate a new paper before committing its import | 0.331 | 0.309 | 0.365 | **0.335** |
| R17 | Lock an owned active attempt before saving or submitting | 0.055 | 0.028 | 0.017 | **0.033** |
| R18 | Check database connectivity | 0.002 | 0.002 | 0.001 | **0.002** |

## WRITE timings

| ID | Query | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| W1 | Register a student with a backend-generated password hash | 0.245 | 0.032 | 0.051 | **0.109** |
| W2 | Create an attempt if this student has no active attempt on the paper | 1.657 | 0.117 | 0.092 | **0.622** |
| W3 | Save numerical/choice answer state, review flag and cumulative time | 0.614 | 0.159 | 0.136 | **0.303** |
| W4 | Remove the old selected options before replacing or clearing an answer | 0.191 | 0.101 | 0.117 | **0.136** |
| W5 | Insert the complete replacement set of selected options | 0.221 | 0.203 | 0.231 | **0.218** |
| W6 | Submit an owned active attempt | 0.105 | 0.025 | 0.033 | **0.054** |
| W7 | Close an expired active attempt before starting another | 0.032 | 0.033 | 0.027 | **0.031** |
| W8 | Create a taxonomy subject if it does not already exist | 0.052 | 0.019 | 0.017 | **0.029** |
| W9 | Create a chapter within its subject | 0.079 | 0.029 | 0.029 | **0.046** |
| W10 | Create a topic within its chapter | 0.072 | 0.024 | 0.029 | **0.042** |
| W11 | Create a new verified question/version | 0.110 | 0.029 | 0.036 | **0.058** |
| W12 | Assign the new question its optional primary topic | 0.074 | 0.034 | 0.032 | **0.047** |
| W13 | Add one option to a new choice question | 0.126 | 0.028 | 0.023 | **0.059** |
| W14 | Record a correct option for a new choice question | 0.049 | 0.018 | 0.021 | **0.029** |
| W15 | Record an inclusive numerical answer range | 0.049 | 0.025 | 0.034 | **0.036** |
| W16 | Add an ordered image to a new question | 0.053 | 0.024 | 0.027 | **0.035** |
| W17 | Add an ordered image to a new option | 0.058 | 0.021 | 0.029 | **0.036** |
| W18 | Create a new historical paper/version | 0.090 | 0.013 | 0.012 | **0.038** |
| W19 | Place a verified question in the new paper with its marking rules | 0.240 | 0.035 | 0.033 | **0.103** |

## Execution-plan analysis

Each row summarizes the first captured plan's root operation and scan/index operators. The three complete plans for every query are saved as linked run files under [`plans/`](plans/). Operators and buffer counts describe this small fixture and local cache state.

| ID | Plan shape observed | Scan/index operators in run 1 | Captured plans |
|---|---|---|---|
| R1 | `Seq Scan on users` | Seq Scan on users | [run 1](plans/R1_run1.txt), [run 2](plans/R1_run2.txt), [run 3](plans/R1_run3.txt) |
| R2 | `Seq Scan on users` | Seq Scan on users | [run 1](plans/R2_run1.txt), [run 2](plans/R2_run2.txt), [run 3](plans/R2_run3.txt) |
| R3 | `Limit` | Seq Scan on test_questions, Seq Scan on tests | [run 1](plans/R3_run1.txt), [run 2](plans/R3_run2.txt), [run 3](plans/R3_run3.txt) |
| R4 | `Sort` | Seq Scan on tests, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on chapters, Seq Scan on subjects | [run 1](plans/R4_run1.txt), [run 2](plans/R4_run2.txt), [run 3](plans/R4_run3.txt) |
| R5 | `Sort` | Seq Scan on question_topics, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on chapters, Seq Scan on subjects, Seq Scan on topics | [run 1](plans/R5_run1.txt), [run 2](plans/R5_run2.txt), [run 3](plans/R5_run3.txt) |
| R6 | `GroupAggregate` | Seq Scan on question_options, Seq Scan on test_questions, Seq Scan on option_images | [run 1](plans/R6_run1.txt), [run 2](plans/R6_run2.txt), [run 3](plans/R6_run3.txt) |
| R7 | `Sort` | Seq Scan on test_questions, Seq Scan on question_images | [run 1](plans/R7_run1.txt), [run 2](plans/R7_run2.txt), [run 3](plans/R7_run3.txt) |
| R8 | `Nested Loop` | Seq Scan on attempts, Seq Scan on tests | [run 1](plans/R8_run1.txt), [run 2](plans/R8_run2.txt), [run 3](plans/R8_run3.txt) |
| R9 | `Hash Join` | Seq Scan on tests, Seq Scan on attempts | [run 1](plans/R9_run1.txt), [run 2](plans/R9_run2.txt), [run 3](plans/R9_run3.txt) |
| R10 | `Sort` | Seq Scan on questions, Seq Scan on test_questions, Seq Scan on attempts | [run 1](plans/R10_run1.txt), [run 2](plans/R10_run2.txt), [run 3](plans/R10_run3.txt) |
| R11 | `Sort` | Bitmap Heap Scan on answers, Bitmap Index Scan on answers_pkey, Seq Scan on question_topics, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on attempts, Seq Scan on chapters, Seq Scan on subjects, Seq Scan on topics, Seq Scan on numerical_keys, Seq Scan on correct_options, Bitmap Heap Scan on question_options, Bitmap Index Scan on question_options_pkey | [run 1](plans/R11_run1.txt), [run 2](plans/R11_run2.txt), [run 3](plans/R11_run3.txt) |
| R12 | `GroupAggregate` | Bitmap Heap Scan on answers, Bitmap Index Scan on answers_pkey, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on attempts, Seq Scan on chapters, Seq Scan on subjects, Seq Scan on numerical_keys, Bitmap Heap Scan on question_options, Bitmap Index Scan on question_options_pkey, Seq Scan on correct_options | [run 1](plans/R12_run1.txt), [run 2](plans/R12_run2.txt), [run 3](plans/R12_run3.txt) |
| R13 | `GroupAggregate` | Bitmap Heap Scan on answers, Bitmap Index Scan on answers_pkey, Seq Scan on question_topics, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on attempts, Seq Scan on chapters, Seq Scan on subjects, Seq Scan on topics, Seq Scan on numerical_keys, Seq Scan on correct_options, Bitmap Heap Scan on question_options, Bitmap Index Scan on question_options_pkey | [run 1](plans/R13_run1.txt), [run 2](plans/R13_run2.txt), [run 3](plans/R13_run3.txt) |
| R14 | `Limit` | Seq Scan on attempts, Seq Scan on tests, Seq Scan on answers, Seq Scan on questions, Seq Scan on test_questions, Seq Scan on chapters, Seq Scan on subjects, Seq Scan on numerical_keys, Bitmap Heap Scan on question_options, Bitmap Index Scan on question_options_pkey, Seq Scan on correct_options | [run 1](plans/R14_run1.txt), [run 2](plans/R14_run2.txt), [run 3](plans/R14_run3.txt) |
| R15 | `Sort` | Seq Scan on topics, Seq Scan on chapters, Seq Scan on subjects | [run 1](plans/R15_run1.txt), [run 2](plans/R15_run2.txt), [run 3](plans/R15_run3.txt) |
| R16 | `Sort` | Seq Scan on questions, Seq Scan on test_questions, Bitmap Heap Scan on question_options, Bitmap Index Scan on question_options_pkey, Seq Scan on correct_options, Seq Scan on numerical_keys, Seq Scan on option_images, Seq Scan on question_options, Seq Scan on tests | [run 1](plans/R16_run1.txt), [run 2](plans/R16_run2.txt), [run 3](plans/R16_run3.txt) |
| R17 | `LockRows` | Seq Scan on tests, Seq Scan on attempts | [run 1](plans/R17_run1.txt), [run 2](plans/R17_run2.txt), [run 3](plans/R17_run3.txt) |
| R18 | `Result` | none reported | [run 1](plans/R18_run1.txt), [run 2](plans/R18_run2.txt), [run 3](plans/R18_run3.txt) |
| W1 | `Insert on users` | none reported | [run 1](plans/W1_run1.txt), [run 2](plans/W1_run2.txt), [run 3](plans/W1_run3.txt) |
| W2 | `Insert on attempts` | Seq Scan on users, Seq Scan on tests, Seq Scan on test_questions | [run 1](plans/W2_run1.txt), [run 2](plans/W2_run2.txt), [run 3](plans/W2_run3.txt) |
| W3 | `Insert on answers existing` | Seq Scan on test_questions, Seq Scan on tests, Seq Scan on attempts | [run 1](plans/W3_run1.txt), [run 2](plans/W3_run2.txt), [run 3](plans/W3_run3.txt) |
| W4 | `Delete on answer_options selected` | Seq Scan on attempts | [run 1](plans/W4_run1.txt), [run 2](plans/W4_run2.txt), [run 3](plans/W4_run3.txt) |
| W5 | `Insert on answer_options` | Seq Scan on attempts | [run 1](plans/W5_run1.txt), [run 2](plans/W5_run2.txt), [run 3](plans/W5_run3.txt) |
| W6 | `Update on attempts` | Seq Scan on attempts | [run 1](plans/W6_run1.txt), [run 2](plans/W6_run2.txt), [run 3](plans/W6_run3.txt) |
| W7 | `Update on attempts attempt` | Seq Scan on attempts, Seq Scan on tests | [run 1](plans/W7_run1.txt), [run 2](plans/W7_run2.txt), [run 3](plans/W7_run3.txt) |
| W8 | `Insert on subjects` | none reported | [run 1](plans/W8_run1.txt), [run 2](plans/W8_run2.txt), [run 3](plans/W8_run3.txt) |
| W9 | `Insert on chapters` | none reported | [run 1](plans/W9_run1.txt), [run 2](plans/W9_run2.txt), [run 3](plans/W9_run3.txt) |
| W10 | `Insert on topics` | none reported | [run 1](plans/W10_run1.txt), [run 2](plans/W10_run2.txt), [run 3](plans/W10_run3.txt) |
| W11 | `Insert on questions` | none reported | [run 1](plans/W11_run1.txt), [run 2](plans/W11_run2.txt), [run 3](plans/W11_run3.txt) |
| W12 | `Insert on question_topics` | none reported | [run 1](plans/W12_run1.txt), [run 2](plans/W12_run2.txt), [run 3](plans/W12_run3.txt) |
| W13 | `Insert on question_options` | none reported | [run 1](plans/W13_run1.txt), [run 2](plans/W13_run2.txt), [run 3](plans/W13_run3.txt) |
| W14 | `Insert on correct_options` | none reported | [run 1](plans/W14_run1.txt), [run 2](plans/W14_run2.txt), [run 3](plans/W14_run3.txt) |
| W15 | `Insert on numerical_keys` | none reported | [run 1](plans/W15_run1.txt), [run 2](plans/W15_run2.txt), [run 3](plans/W15_run3.txt) |
| W16 | `Insert on question_images` | none reported | [run 1](plans/W16_run1.txt), [run 2](plans/W16_run2.txt), [run 3](plans/W16_run3.txt) |
| W17 | `Insert on option_images` | none reported | [run 1](plans/W17_run1.txt), [run 2](plans/W17_run2.txt), [run 3](plans/W17_run3.txt) |
| W18 | `Insert on tests` | none reported | [run 1](plans/W18_run1.txt), [run 2](plans/W18_run2.txt), [run 3](plans/W18_run3.txt) |
| W19 | `Insert on test_questions` | none reported | [run 1](plans/W19_run1.txt), [run 2](plans/W19_run2.txt), [run 3](plans/W19_run3.txt) |

## Observations and possible optimizations

- Most simple lookup and CRUD queries execute in under one millisecond. The more complex submitted-attempt evaluation and analytics queries, particularly R11–R14, require comparatively more processing time. Most pages were served from shared-buffer hits; these numbers describe this local fixture and should not be treated as production capacity estimates. Sequential scans on the small fixture (for example, R1 scans 20 users and R3 scans 6 papers / 120 placements) are expected planner choices. Do not add indexes solely to avoid these scans at this scale.
- R12 and R14 were the slowest READs in this sample (averages shown above). Their plans evaluate substantial result/history logic, with repeated scoring CTEs and correlated subplans. If these dominate at realistic scale, compare a refactored shared scoring query or maintained result summary against the current canonical calculation, while preserving invalid-key handling, unanswered rows and ownership checks.
- R11 and R13 also perform multi-table answer evaluation. Their plans show repeated key/option lookups and joins. With production-sized data, inspect loop counts and buffer reads first; the primary/foreign-key indexes already cover many joins and lookups.
- R3's substring `ILIKE` title search is not supported by a conventional B-tree index. If title search becomes a measured bottleneck on a large paper catalogue, evaluate `pg_trgm` with a GIN index. Optional-parameter predicates may also benefit from separate filtered/unfiltered statement shapes if plans show poor selectivity estimates.
- R6 aggregates ordered image JSON per option. If image volume grows, measure the grouped join and consider pre-aggregating image payloads only if its cost is material.
- Several write plans include trigger and constraint work, particularly answer saves (W3/W5). That work enforces the project's ownership/type/deadline integrity behavior. Optimize it only after measuring on a realistic data volume and preserving those checks.
- First-run values (notably write lookups/inserts) vary from subsequent runs due to cache warm-up and plan/runtime overhead. Three-run averages are reported transparently; no timing values were fabricated or normalized.

## Verification

- Captured 111 plan files: three per query ID (37 × 3); all include an `Execution Time` line.
- Verified the database name is `cutoff_cp4_bench_2026`; no connection or command targeted the existing `cutoff` database.
- Write statements were run in explicit transactions and rolled back. Fixture setup for each individual write plan was also rolled back.
- The schema and query SQL were only read, not edited.