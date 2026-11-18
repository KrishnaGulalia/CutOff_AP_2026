# Cutoff — Entity–Relationship Diagram

The main diagram groups the 16 tables into **classification**, **question bank**,
**papers**, and **student activity**. It matches the 65 columns and 18 foreign
keys in [03_schema.sql](03_schema.sql).

Open the [zoomable SVG](02_er_diagram.svg), [high-resolution PNG](02_er_diagram.png),
or [editable Draw.io source](02_er_diagram.drawio).

![Cutoff entity–relationship diagram](02_er_diagram.svg)

Connector labels identify the foreign-key columns. Crow's-foot symbols show
whether a relationship allows exactly one, zero or one, or zero or many rows.
`PK` and `FK` mark every participating column, including composite keys.
`UQ` marks unique constraints; composite sets are written below their tables.
`UQ*` marks the rule allowing only one active attempt per student and paper.
Only columns marked `NULL` are nullable.

Edit the `.drawio` file and export both SVG and PNG when changing the main diagram.
Keep the SQL schema and the Mermaid source below consistent with those changes.

## Mermaid version with named relationships

This alternate view labels relationships with verbs such as “starts”, “contains”,
and “records”. Its editable source is [02_er_diagram.mmd](02_er_diagram.mmd).

```mermaid
erDiagram
    direction TB
    subjects {
        bigint subject_id PK
        text subject_name UK
    }
    users {
        bigint user_id PK
        text user_name
        text email UK
        text password_hash
        timestamptz user_created_at
        timestamptz user_updated_at
    }
    tests {
        bigint test_id PK
        text test_title
        smallint exam_year
        text session_label
        integer duration_minutes
        timestamptz test_created_at
    }
    chapters {
        bigint chapter_id PK
        bigint subject_id FK
        text chapter_name
    }
    topics {
        bigint topic_id PK
        bigint chapter_id FK
        text topic_name
    }
    questions {
        bigint question_id PK
        bigint chapter_id FK
        text question_text
        text question_type
        text difficulty
        text explanation_text "nullable"
        timestamptz question_created_at
    }
    attempts {
        bigint attempt_id PK
        bigint user_id FK
        bigint test_id FK
        timestamptz started_at
        timestamptz submitted_at "nullable"
        text attempt_status
    }
    question_topics {
        bigint question_id PK, FK
        bigint topic_id FK
    }
    question_images {
        bigint question_id PK, FK
        integer image_position PK
        text image_url
    }
    numerical_keys {
        bigint question_id PK, FK
        numeric accepted_min
        numeric accepted_max
    }
    question_options {
        bigint question_id PK, FK
        text option_label PK
        text option_text
    }
    test_questions {
        bigint test_id PK, FK
        bigint question_id PK, FK
        integer position
        numeric marks_correct
        numeric marks_incorrect
        numeric marks_unattempted
    }
    answers {
        bigint attempt_id PK, FK
        bigint question_id PK, FK
        numeric numerical_response "nullable"
        boolean marked_for_review
        integer time_spent_seconds
        timestamptz answer_updated_at
    }
    option_images {
        bigint question_id PK, FK
        text option_label PK, FK
        integer image_position PK
        text image_url
    }
    correct_options {
        bigint question_id PK, FK
        text option_label PK, FK
    }
    answer_options {
        bigint attempt_id PK, FK
        bigint question_id PK, FK
        text option_label PK, FK
    }
    answers ||--o{ answer_options : "contains selections"
    question_options ||--o{ answer_options : "is selected in"
    attempts ||--o{ answers : "records"
    questions ||--o{ answers : "receives answers"
    tests ||..o{ attempts : "receives"
    users ||..o{ attempts : "starts"
    subjects ||..o{ chapters : "contains"
    question_options ||--o| correct_options : "is marked correct"
    questions ||--o| numerical_keys : "has numerical key"
    question_options ||--o{ option_images : "has images"
    questions ||--o{ question_images : "has images"
    questions ||--o{ question_options : "offers"
    questions ||--o| question_topics : "has topic assignment"
    topics ||..o{ question_topics : "classifies through"
    chapters ||..o{ questions : "classifies"
    questions ||--o{ test_questions : "appears in"
    tests ||--o{ test_questions : "contains"
    chapters ||..o{ topics : "contains"
```

`PK` = primary key; `FK` = foreign key; `UK` = unique key.
All PK-marked columns form one composite primary key where applicable.
Solid lines identify relationships whose FK columns form part of the child PK;
dashed lines identify the other relationships.

Composite unique constraints: `chapters(subject_id, chapter_name)`,
`topics(chapter_id, topic_name)`, and `test_questions(test_id, position)`.
`attempts(user_id, test_id)` is unique only while `attempt_status = IN_PROGRESS`.

