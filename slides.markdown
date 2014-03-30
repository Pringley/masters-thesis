---
title: Dynamic language bridges and applications in LED patent citation analysis
author: Benjamin Pringle
date: April 1, 2014
...

# Introduction

## Language bridges

A **language bridge** allows a program written in one language to use functions
or libraries from a different language.

*Example*: Web server frontend written in Ruby calls backend functions in
Java.

## Existing techniques -- shared runtime environment

Multiple languages with a single runtime environment usually have bridging
built-in.

-   Common Language Runtime

    -   Used by .NET Framework
    -   Languages include C++, C#, Visual Basic, IronPython

-   Java Virtual Machine

    -   Many languages compile to JVM bytecode
    -   Languages include Java, Scala, Clojure, Groovy, Jython

*Example*: Frontend written in Jython can call backend functions in Java as if
they were native.

## Existing techniques -- foreign function interface

Allows use of routines in a lower-level language, typically C.

-   Easy for dynamic languages implemented in C

    -   CPython, CRuby

-   Other languages also have FFI

    -   Java Native Interface supports calls from Java to C, C++, assembly

Usually requires "glue code" at the native level.

## Existing techniques -- remote procedure call

Send requests from one language to another via network protocols.

-   XML-RPC, SOAP -- general XML over HTTP protocol
-   JSON-RPC -- similar to XML-RPC, uses

Usually requires glue code on the client and/or server to

## Missing use case -- zero-configuration cross-runtime bridge

-   Shared runtime requires no configuration, but limited in languages

    -   As of April 2014, latest Jython release is 2.5, while latest CPython is 3.4
    -   Jython does not support C-backed libraries such as NumPy and SciPy

-   FFI and RPC require glue code

    -   Too much work for small projects or research

## Prior art -- RPC interface generation

**Apache Thrift** is an RPC framework developed by Facebook.

-   Automatically generates most client/server glue code

-   Still requires configuration file(s) to generate server code

-   Still may require some glue code for existing libraries

## Prior art -- dynamic FFI

-   **RubyPython** uses FFI to transparently call CPython from CRuby.

    -   Dynamic -- requires no glue code *or* configuration
    -   Does *not* work cross runtime (e.g. call Jython from CRuby)
    -   Only works from CRuby to CPython, no other direction or other languages

-   **JyNI** uses FFI from Jython to CPython

    -   Dynamic -- requires no glue code *or* configuration
    -   Cross-runtime -- from Java to CPython
    -   **Incomplete**
        -   Does not work with most of CPython standard library
        -   Does not work with NumPy, SciPy

## New idea -- dynamic RPC

Basic new idea: **dynamic RPC server** for scripting languages.

-   Network protocol similar to JSON-RPC, sent over pipes

-   Backend is *automatically generated* using introspection and
    metaprogramming

-   Client library uses proxy objects to make RPC calls transparent (i.e. the
    code "looks like" regular use of the source language)

# Bifrost: A Dynamic RPC Protocol

# Case Study of Approaches to Finding Patterns in LED Patent Citation Networks

# Conclusion
