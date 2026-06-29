---
title: "What exactly is JVM ?"
postSlug: what-exactly-is-jvm
author: Cuong
date: 2026-06-29
description: "Learning JVM like a madman PART 1"
tags:
  - java
  - jvm
---

## What do other languages do?
When you compile a program written in C, it gets compiled to a "native binary" which means that it ends up as architecture specific machine code. To run a program which has been built using Linux on an X86 processor on an Arm processor or on a different OS such as Windows, it will at the least need to be recompiled for the platform. Depending on the program, you may need to rewrite some or much of it as well.

## What does JVM do?
The JVM is a virtual machine that sits on top of the operating system.

Every os/system has their own jvm specific to their api/machine code. Java files are compiled not into machine code but rather into an in-between code called bytecode. The jvm understands java bytecode and then translates that to the os/platform/system specific machine code calls. 

Here is an example, first : 
```text
Windows
   javac
      │
      ▼
Bytecode (.class)
```
> The bytecode is defined by the Java Virtual Machine Specification, not by Windows.

Later : 
```text
Linux JVM
    │
    ▼
Native Linux machine code

macOS JVM
    │
    ▼
Native macOS machine code

Windows JVM
    │
    ▼
Native Windows machine code
```
> Each JVM translates the same bytecode into instructions for its own operating system and CPU.

## Benefits of JVM ?
So we know what is jvm, and what it do but what acctually the benefit of JVM ? 
Or the real question is what the benefit of interpreted langueges (java, python, ..) compare to compiled language (c++, golang,...). This answer for this question will be discussion in another blog in furture. For now , i will list some benefits of JVM :  

1. Platform Independence
The same .class file runs on Windows, Linux, and macOS without changes.
=> This is what gives Java its famous property: “Write once, run anywhere.”

2. Automatic Memory Management
You don’t manually allocate and free memory.
The JVM handles memory through Garbage Collection.

3. Security
Before running, the JVM verifies the bytecode to ensure it is safe.

4. Rich Runtime Features
The JVM provides:
* Reflection
* Dynamic class loading
* Hot code replacement
* Runtime profiling
* Portable threading APIs

These are much harder to implement in a pure native executable and this feature which powers by one of the famous java framework : SpringBoot.