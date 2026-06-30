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

Every OS/system has its own JVM specific to its API/machine code. Java files are compiled not into machine code but rather into an in-between code called bytecode. The JVM understands Java bytecode and then translates it into the OS/platform/system-specific machine code calls.

Here is an example. First:
```text
Windows
   javac
      │
      ▼
Bytecode (.class)
```
> The bytecode is defined by the Java Virtual Machine Specification, not by Windows.

Later:
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

## The JVM is more than bytecode translation
After the sections above, we can simply say that:

```text
JVM converts bytecode to machine code.
```

So the answer is not wrong, but it is incomplete. To completely understand the JVM, we will go into some topics:

### What is a virtual machine?
```text
A virtual machine is a software system that behaves like a machine.
```

There are two categories of virtual machines:

A. System Virtual Machine
+ VMware
+ Hyper-V
+ VirtualBox
+ KVM

Each VM has:
+ its own OS
+ memory
+ processes
+ filesystem

B. Application Virtual Machine
Instead of virtualizing an entire computer, it virtualizes `an execution environment for applications`. For example:
+ JVM
+ .NET CLR
+ Parrot VM
The JVM doesn't emulate an entire computer. It only provides an environment for running Java programs.

### JVM is specification
Oracle publishes The Java Virtual Machine Specification (and HotSpot is only one implementation of the JVM) (https://docs.oracle.com/javase/specs/jvms/se21/jvms21.pdf). It defines:
```text
                JVM

      ┌─────────────────────┐
      │ Class Loader        │
      │ Bytecode Verifier   │
      │ Interpreter         │
      │ JIT Compiler        │
      │ Garbage Collector   │
      │ Memory Manager      │
      │ Thread Scheduler    │
      │ Exception Handling  │
      │ Reflection Support  │
      │ Native Interface    │
      └─────────────────────┘
```

Bytecode translation is only one component (Interpreter + JIT). The JVM is responsible for the entire lifecycle of a Java program.

### Other benefits of the JVM?
So we know what the JVM is and what it does, but what is actually the benefit of the JVM?
Or, the real question is: what are the benefits of interpreted languages (Java, Python, ...) compared to compiled languages (C++, Golang, ...)? The answer to this question will be discussed in another blog in the future. For now, I will list some benefits of the JVM:

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

These are much harder to implement in a pure native executable, and they are the features that power one of the most famous Java frameworks: Spring Boot.