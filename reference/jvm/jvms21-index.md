# JVMS 21 — Navigation Index

Reference: **The Java® Virtual Machine Specification, Java SE 21 Edition**
(Lindholm, Yellin, Bracha, Buckley, Smith — Aug 2023)
File: `reference/pdfs/jvms21.pdf` (626 pages)

## How to read a section

Page numbers below are the spec's **printed** page numbers (from its Table of
Contents). The PDF has 10 pages of front matter, so:

> **PDF page = printed page + 10**

When reading with the Read tool's `pages` param, convert first.
Example: §2.5 Run-Time Data Areas is printed p.11 → read PDF page **21**.
(Read PDFs in windows of ≤20 pages.)

## Chapter map (printed pages)

| Ch | Title | Printed p. | PDF p. |
|----|-------|-----------|--------|
| 1 | Introduction | 1 | 11 |
| 2 | The Structure of the Java Virtual Machine | 5 | 15 |
| 3 | Compiling for the Java Virtual Machine | 39 | 49 |
| 4 | The `class` File Format | 71 | 81 |
| 5 | Loading, Linking, and Initializing | 363 | 373 |
| 6 | The Java Virtual Machine Instruction Set | 405 | 415 |
| 7 | Opcode Mnemonics by Opcode | 607 | 617 |
| A | Limited License Grant | 611 | 621 |

## Chapter 2 — Structure (the core mental-model chapter)

| § | Topic | Printed p. |
|---|-------|-----------|
| 2.2 | Data Types | 6 |
| 2.3 | Primitive Types and Values (integral, float, returnAddress, boolean) | 6 |
| 2.4 | Reference Types and Values | 10 |
| 2.5 | **Run-Time Data Areas** | 11 |
| 2.5.1 | The pc Register | 11 |
| 2.5.2 | Java Virtual Machine Stacks | 11 |
| 2.5.3 | Heap | 12 |
| 2.5.4 | Method Area | 13 |
| 2.5.5 | Run-Time Constant Pool | 13 |
| 2.5.6 | Native Method Stacks | 14 |
| 2.6 | Frames (local vars, operand stack, dynamic linking) | 15 |
| 2.7 | Representation of Objects | 18 |
| 2.8 | Floating-Point Arithmetic | 18 |
| 2.9 | Special Methods (`<init>`, `<clinit>`, signature-polymorphic) | 22 |
| 2.10 | Exceptions | 24 |
| 2.11 | Instruction Set Summary | 26 |
| 2.12 | Class Libraries | 36 |
| 2.13 | Public Design, Private Implementation | 37 |

## Chapter 4 — `class` File Format (frequently referenced)

| § | Topic | Printed p. |
|---|-------|-----------|
| 4.1 | The ClassFile Structure | 72 |
| 4.3 | Descriptors (field & method) | 80 |
| 4.4 | The Constant Pool (all CONSTANT_* structures) | 83 |
| 4.5 | Fields | 99 |
| 4.6 | Methods | 101 |
| 4.7 | Attributes (Code, StackMapTable, LineNumberTable, annotations, …) | 105 |
| 4.7.3 | The Code Attribute | 114 |
| 4.7.4 | The StackMapTable Attribute | 117 |
| 4.9 | Constraints on JVM Code | 188 |
| 4.10 | Verification of `class` Files | 196 |

## Chapter 5 — Loading, Linking, Initializing

| § | Topic | Printed p. |
|---|-------|-----------|
| 5.1 | The Run-Time Constant Pool | 363 |
| 5.2 | JVM Startup | 366 |
| 5.3 | Creation and Loading (bootstrap & user-defined loaders, arrays) | 367 |
| 5.4 | Linking (verification, preparation, resolution) | 378 |
| 5.4.3 | Resolution (class, field, method, invokedynamic) | 380 |
| 5.4.4 | Access Control | 396 |
| 5.5 | Initialization | ~401 |
| 5.6 | Binding Native Method Implementations | 403 |
| 5.7 | JVM Termination | 403 |

## Chapter 6 — Instruction Set

Section 6.5 is the alphabetical opcode reference (`aaload` … `wide`),
one instruction per entry, printed pp. ~430–604.
For a specific opcode, use **Chapter 7 (printed p.607 / PDF p.617)** to find
its number, or jump into 6.5 alphabetically.

| § | Topic | Printed p. |
|---|-------|-----------|
| 6.1 | Assumptions: The Meaning of "Must" | 405 |
| 6.3 | Virtual Machine Errors | 405 |
| 6.4 | Format of Instruction Descriptions | 405 |
| 6.5 | The Java Virtual Machine Instructions (opcode reference) | ~430 |
