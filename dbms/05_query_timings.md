# CP4 Query Performance Analysis

## Method

- PostgreSQL 18.6 (Postgres.app), local server. The isolated database `cutoff_cp4_bench_2026` contains the schema from `03_schema.sql` and a realistic synthetic fixture; the application database `cutoff` was not selected for any benchmark command.
- Fixture scale: 20 students, 3 subjects, 6 chapters, 12 topics, 120 questions, 6 papers (20 questions each), 33 attempts, 640 saved answer states and 512 selected-option rows.
- Every prepared statement R1–R18 and W1–W19 was run three times as `EXPLAIN (ANALYZE, BUFFERS) EXECUTE ...` using valid fixture parameters.
- Each write run, including any prerequisite rows, ran in a transaction that ended in `ROLLBACK`; none of the benchmark writes persisted.
- Values are PostgreSQL `Execution Time` from the corresponding captured plan. Average is the arithmetic mean of the three displayed runs, rounded to 0.001 ms.
- Each plan file contains all three actual plans for that query, including planning details, actual rows, buffer counts, and trigger timings where reported.

## Timing results

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type(s), run 1 |
|---|---|---|---:|---:|---:|---:|---|
| [R1](plans/R1.txt) | READ | Find an account for login or duplicate-email checking | 0.016 | 0.005 | 0.003 | **0.008** | `Seq Scan on users` |
| [R2](plans/R2.txt) | READ | Read the signed-in student profile | 0.003 | 0.003 | 0.002 | **0.003** | `Seq Scan on users` |
| [R3](plans/R3.txt) | READ | Browse papers with optional filters and pagination | 0.088 | 0.041 | 0.035 | **0.055** | `Seq Scan on test_questions`, `Seq Scan on tests` |
| [R4](plans/R4.txt) | READ | Read paper details and subject-wise question/mark counts | 0.436 | 0.046 | 0.042 | **0.175** | `Seq Scan on tests`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on chapters`, `Seq Scan on subjects` |
| [R5](plans/R5.txt) | READ | Deliver paper questions without answers or explanations | 0.066 | 0.051 | 0.058 | **0.058** | `Seq Scan on question_topics`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on chapters`, `Seq Scan on subjects`, `Seq Scan on topics` |
| [R6](plans/R6.txt) | READ | Deliver choice options and their ordered images | 0.387 | 0.075 | 0.071 | **0.178** | `Seq Scan on question_options`, `Seq Scan on test_questions`, `Seq Scan on option_images` |
| [R7](plans/R7.txt) | READ | Deliver ordered question images | 0.015 | 0.011 | 0.010 | **0.012** | `Seq Scan on test_questions`, `Seq Scan on question_images` |
| [R8](plans/R8.txt) | READ | Find the current resumable attempt | 0.069 | 0.008 | 0.006 | **0.028** | `Seq Scan on attempts`, `Seq Scan on tests` |
| [R9](plans/R9.txt) | READ | Read an owned attempt and its timer | 0.033 | 0.009 | 0.008 | **0.017** | `Seq Scan on tests`, `Seq Scan on attempts` |
| [R10](plans/R10.txt) | READ | Restore question navigation, review flags and saved responses | 0.545 | 0.041 | 0.039 | **0.208** | `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on attempts` |
| [R11](plans/R11.txt) | READ | Review and score every question in a submitted attempt | 1.029 | 0.704 | 0.677 | **0.803** | `Bitmap Heap Scan on answers`, `Bitmap Index Scan on answers_pkey`, `Seq Scan on question_topics`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on attempts`, `Seq Scan on chapters`, `Seq Scan on subjects`, `Seq Scan on topics`, `Seq Scan on numerical_keys`, `Seq Scan on correct_options`, `Bitmap Heap Scan on question_options`, `Bitmap Index Scan on question_options_pkey` |
| [R12](plans/R12.txt) | READ | Calculate the result summary | 2.462 | 2.146 | 2.647 | **2.418** | `Bitmap Heap Scan on answers`, `Bitmap Index Scan on answers_pkey`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on attempts`, `Seq Scan on chapters`, `Seq Scan on subjects`, `Seq Scan on numerical_keys`, `Bitmap Heap Scan on question_options`, `Bitmap Index Scan on question_options_pkey`, `Seq Scan on correct_options` |
| [R13](plans/R13.txt) | READ | Analyse subject, chapter, topic, difficulty and time usage | 0.873 | 0.771 | 1.719 | **1.121** | `Bitmap Heap Scan on answers`, `Bitmap Index Scan on answers_pkey`, `Seq Scan on question_topics`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on attempts`, `Seq Scan on chapters`, `Seq Scan on subjects`, `Seq Scan on topics`, `Seq Scan on numerical_keys`, `Seq Scan on correct_options`, `Bitmap Heap Scan on question_options`, `Bitmap Index Scan on question_options_pkey`, `CTE Scan on scored_answers` |
| [R14](plans/R14.txt) | READ | List a student's attempt history with submitted result summaries | 1.728 | 1.446 | 1.592 | **1.589** | `Seq Scan on attempts`, `Seq Scan on tests`, `Seq Scan on answers`, `Seq Scan on questions`, `Seq Scan on test_questions`, `Seq Scan on chapters`, `Seq Scan on subjects`, `Seq Scan on numerical_keys`, `Bitmap Heap Scan on question_options`, `Bitmap Index Scan on question_options_pkey`, `Seq Scan on correct_options` |
| [R15](plans/R15.txt) | READ | Resolve the shared subject/chapter/topic taxonomy | 0.031 | 0.028 | 0.021 | **0.027** | `Seq Scan on topics`, `Seq Scan on chapters`, `Seq Scan on subjects` |
| [R16](plans/R16.txt) | READ | Validate a new paper before committing its import | 0.208 | 0.201 | 0.190 | **0.200** | `Seq Scan on questions`, `Seq Scan on test_questions`, `Bitmap Heap Scan on question_options`, `Bitmap Index Scan on question_options_pkey`, `Seq Scan on correct_options`, `Seq Scan on numerical_keys`, `Seq Scan on option_images`, `Seq Scan on question_options`, `Seq Scan on tests`, `CTE Scan on inspection` |
| [R17](plans/R17.txt) | READ | Lock an owned active attempt before saving or submitting | 0.039 | 0.018 | 0.015 | **0.024** | `Seq Scan on tests`, `Seq Scan on attempts` |
| [R18](plans/R18.txt) | READ | Check database connectivity | 0.001 | 0.001 | 0.001 | **0.001** | No scan node (constant input / DML root) |
| [W1](plans/W1.txt) | WRITE | Register a student with a backend-generated password hash | 1.779 | 0.024 | 0.020 | **0.608** | No scan node (constant input / DML root) |
| [W2](plans/W2.txt) | WRITE | Create an attempt if this student has no active attempt on the paper | 7.724 | 0.061 | 0.063 | **2.616** | `Seq Scan on users`, `Seq Scan on tests`, `Seq Scan on test_questions` |
| [W3](plans/W3.txt) | WRITE | Save numerical/choice answer state, review flag and cumulative time | 0.565 | 0.016 | 0.014 | **0.198** | `Seq Scan on test_questions`, `Seq Scan on tests`, `Seq Scan on attempts` |
| [W4](plans/W4.txt) | WRITE | Remove the old selected options before replacing or clearing an answer | 0.126 | 0.094 | 0.062 | **0.094** | `Seq Scan on attempts` |
| [W5](plans/W5.txt) | WRITE | Insert the complete replacement set of selected options | 0.169 | 0.130 | 0.152 | **0.150** | `Seq Scan on attempts` |
| [W6](plans/W6.txt) | WRITE | Submit an owned active attempt | 0.063 | 0.020 | 0.016 | **0.033** | `Seq Scan on attempts` |
| [W7](plans/W7.txt) | WRITE | Close an expired active attempt before starting another | 0.020 | 0.021 | 0.016 | **0.019** | `Seq Scan on attempts`, `Seq Scan on tests` |
| [W8](plans/W8.txt) | WRITE | Create a taxonomy subject if it does not already exist | 0.183 | 0.010 | 0.006 | **0.066** | No scan node (constant input / DML root) |
| [W9](plans/W9.txt) | WRITE | Create a chapter within its subject | 0.235 | 0.024 | 0.019 | **0.093** | No scan node (constant input / DML root) |
| [W10](plans/W10.txt) | WRITE | Create a topic within its chapter | 0.116 | 0.016 | 0.017 | **0.050** | No scan node (constant input / DML root) |
| [W11](plans/W11.txt) | WRITE | Create a new verified question/version | 0.270 | 0.025 | 0.019 | **0.105** | No scan node (constant input / DML root) |
| [W12](plans/W12.txt) | WRITE | Assign the new question its optional primary topic | 0.049 | 0.021 | 0.020 | **0.030** | No scan node (constant input / DML root) |
| [W13](plans/W13.txt) | WRITE | Add one option to a new choice question | 0.102 | 0.015 | 0.017 | **0.045** | No scan node (constant input / DML root) |
| [W14](plans/W14.txt) | WRITE | Record a correct option for a new choice question | 0.044 | 0.012 | 0.012 | **0.023** | No scan node (constant input / DML root) |
| [W15](plans/W15.txt) | WRITE | Record an inclusive numerical answer range | 0.038 | 0.018 | 0.019 | **0.025** | No scan node (constant input / DML root) |
| [W16](plans/W16.txt) | WRITE | Add an ordered image to a new question | 0.034 | 0.017 | 0.016 | **0.022** | No scan node (constant input / DML root) |
| [W17](plans/W17.txt) | WRITE | Add an ordered image to a new option | 0.032 | 0.016 | 0.016 | **0.021** | No scan node (constant input / DML root) |
| [W18](plans/W18.txt) | WRITE | Create a new historical paper/version | 0.181 | 0.017 | 0.015 | **0.071** | No scan node (constant input / DML root) |
| [W19](plans/W19.txt) | WRITE | Place a verified question in the new paper with its marking rules | 0.581 | 0.036 | 0.031 | **0.216** | No scan node (constant input / DML root) |

## Plan analysis and observations

- The fixture is intentionally modest. PostgreSQL chooses sequential scans for many relations because they contain only a few to a few hundred rows; these plans do not justify adding indexes for this fixture alone.
- R12 and R14 are the most involved READ plans: they repeat submitted-attempt scoring/history logic with joins, aggregates and correlated option/key lookups. On production-sized data, inspect buffer reads, loops and row estimates; consider shared scoring logic or a materialized result only if measurements justify it and all ownership, invalid-key and unanswered-question behavior is preserved.
- R11 and R13 also evaluate answers across multiple relations. Primary and foreign-key indexes cover key lookups, while the small fixture makes several full scans cheaper to the planner. Benchmark at representative scale before changing indexing or query shape.
- R3 applies substring `ILIKE` to paper titles. If catalogue search becomes a measured bottleneck at scale, evaluate `pg_trgm` with a GIN index. Optional filter predicates may warrant distinct statement shapes if estimates or plans are poor.
- R6 performs ordered JSON aggregation for option images. Its captured plan is small; measure larger image sets before considering pre-aggregation.
- Write plans include trigger and foreign-key work. For answer writes, this cost preserves attempt ownership/type/deadline rules; any optimization should retain these integrity checks.
- First-run and later-run times vary with cache warm-up and runtime overhead. All values are direct PostgreSQL measurements; none are fabricated or scaled.

## Verification

- 37 distinct query IDs were measured three times each (111 plan executions). Every plan includes an actual `Execution Time` line.
- The target database throughout was `cutoff_cp4_bench_2026`; the existing `cutoff` database was not changed.
- Final fixture counts remained users=20, tests=6, questions=120, test_questions=120, attempts=33, answers=640, answer_options=512; benchmark writes were rolled back.
- `03_schema.sql` and `04_queries.sql` were used as-is.
