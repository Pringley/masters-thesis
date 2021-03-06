---
title: Dynamic language bridges and applications in LED patent citation analysis
author: Benjamin Pringle
date: April 1, 2014
...

## Acknowledgements

Thank you to my advisor, **Mukkai Krishnamoorthy**, and to my other committee
members, **Bülent Yener** and **David Spooner**.

## Outline

-   **Introduction**

    -   Language bridges
    -   Existing techniques

-   **Bifrost: A Dynamic RPC Protocol**

    -   Protocol
    -   Implementation

-   **Case Study of Approaches to Finding Patterns in LED Patent Citation
    Networks**

-   **Conclusion**

    -   Comparison to prior art

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

Usually requires glue code on the client and/or server.

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

## Contribution -- dynamic RPC

Basic new idea: **dynamic RPC server** for scripting languages.

-   Network protocol similar to JSON-RPC, sent over pipes

-   Backend is *automatically generated* using introspection and
    metaprogramming

-   Client library uses proxy objects to make RPC calls transparent (i.e. the
    code "looks like" regular use of the source language)

# Bifrost: A Dynamic RPC Protocol

## Protocol overview -- example 1 -- loading a module

Example: request for the server to load the module NumPy

```javascript
{ "module": "numpy" }
```

Response:

```javascript
{ "result": {"__bf_oid__": 42} }
```

## Protocol overview -- example 2 -- simple request

Example: request for `numpy.mean` of the array `[1, 2, 3, 4]`

```javascript
{
    "method": "mean",
    "oid": 42,
    "params": [ [1, 2, 3, 4] ]
}
```

Response:

```javascript
{ "result": 2.5 }
```

## Protocol overview -- fields

Request:

-   **`method`** is the name of the method to call.

-   **`oid`** is the identifier for the destination-language object that
    contains the method. In this case, `42` is the object ID (`oid`) for NumPy.

-   **`params`** is an array of parameters for the method. In this case, there
    is only one parameter, the array of numbers that we want the mean for
    (`[1, 2, 3, 4]`).

Response

-   **`result`** contains the return value of the called method. Here, the
    result is `2.5`.

-   **`error`** is only defined if an error occurs, and contains an error
    message.

## Protocol overview -- object proxies

Each object on the server is assigned an object ID (`oid`).

Within the protocol, an object is represented using the magic string
`"__bf_oid__"`.

*Example*:

```javascript
{"__bf_oid__": 42}
```

## Protocol overview -- object proxies

### Example: load a module

```javascript
{ "module": "numpy" }                   // request
{ "result": {"__bf_oid__": 42} }        // response

{ "method": "mean",                     // request
  "oid": 42,
  "params": [ [1, 2, 3, 4] ] }
{ "result": 2.5 }                       // response
```

## Protocol overview -- object proxies

### Example: transpose a matrix

Construct a `numpy.ndarray` object.

```javascript
{ "method": "ndarray",                  // request
  "oid": 42,
  "params": [ [[1, 2], [3, 4]] ] }
{ "result": {"__bf_oid__": 64} }        // response
```

Call the `transpose` method.

```javascript
{ "method": "transpose",                // request
  "oid": 42,
  "params": [ {"__bf_oid__": 64} ] }
{ "result": {"__bf_oid__": 144} }       // response
```

## Protocol overview -- object proxies

Get native array from `ndarray` using `tolist()`.

```javascript
{ "method": "tolist",                   // request
  "oid": 144,
  "params": [] }
{ "result": [[1, 3], [2, 4]] }          // response
```

$$\begin{bmatrix}1 & 2 \\ 3 & 4\end{bmatrix}
\to
\begin{bmatrix}1 & 3 \\ 2 & 4\end{bmatrix}$$

## Protocol overview -- JSON types

Parameters and results are represented as JSON types when possible.

Scalar types:

-   string
-   number (`int`, `float`)
-   bool
-   `nil`

Compound types:

-   array
-   object (also called map, dictionary)

## Protocol overview -- non-string keys

In JSON, all dictionary keys *must* be strings.

Use case for non-string keys: Python NetworkX graph library.

-   Create a directed graph from adjacency list:

    ```python
    networkx.DiGraph({1: [2, 4], 2: [3]})
    ```

This dictionary has integer keys, not string-keys!

## Protocol overview -- non-string keys

How to encode Python dictionary `{1: 2, 3: 4}` in JSON as a parameter?

```javascript
/* naive way -- INVALID JSON */
{1: 2, 3: 4}

/* BiFrost way -- marked list of lists */
{"__bf_dict__": [[1, 2], [3, 4]]}
```

## Protocol overview -- non-string keys

We can represent this NetworkX call:
```python
networkx.DiGraph({1: [2, 4], 2: [3]})
```

Using the following Bifrost request:
```javascript
{ "method": "DiGraph",
  "oid": 9,
  "params": {"__bf_dict__": [[1, [2, 4]], [2, [3]]]}
}
```

## Implementation -- overview

1.  Client initializes Bifrost by forking a server process in target language,
    connected by two pipes.

2.  Server initializes and waits for JSON-encoded requests on the client pipe.

3.  Client makes requests and receives responses:

    -   Write JSON-encoded request to client pipe, followed by a newline.
    -   Read JSON-encoded response on server pipe, terminated by a newline.

## Implementation -- dynamic introspection

To avoid writing glue code, server must use introspection to discover methods.

Example: Python server

> **getattr**(*object*, *name*[, *default*])
>
> > Return the value of the named attribute of object. name must be a string.
> > If the string is the name of one of the object’s attributes, the result is
> > the value of that attribute. For example, getattr(x, 'foobar') is
> > equivalent to x.foobar. If the named attribute does not exist, default is
> > returned if provided, otherwise AttributeError is raised.

## Implementation -- dynamic introspection

```python
def handle(request_json):
    # Extract information from request.
    request = json.loads(request_json)
    parameter_list = request['params']
    method_name = request['method']
    object_id = request['oid']

    # Look up object via ID from internal table.
    obj = object_table[object_id]

    # Look up the method name.
    method = getattr(obj, method_name)

    # Call method (with given params).
    result = method(*parameter_list)
    return result
```

## Implementation -- object proxies

Client can also use metaprogramming to increase transparency and eliminate glue
code.

Example: Ruby client

> **method\_missing(symbol[, \*args]) -> result**
>
> Invoked by Ruby when obj is sent a message it cannot handle. symbol is the
> symbol for the method called, and args are any arguments that were passed to
> it. By default, the interpreter raises an error when this method is called.
> However, it is possible to override the method to provide more dynamic
> behavior.

## Implementation -- object proxies

```ruby
class ObjectProxy

  def initialize oid
    # Create a proxy for an object with specific ID
    @oid = oid
  end

  def method_missing(method, *params)
    # Forward all method calls to the server
    send_request @oid, method, params
  end

end
```

## Implementation -- example

Below is client code using a Ruby client and the Python server.

```ruby
require 'rubifrost'

python = RuBifrost.python
# => RuBifrost(server="python3 -mpybifrost.server")

NumPy = python.import 'numpy'
# => RuBifrost::Proxy(oid=42)

NumPy.mean([1, 2, 3, 4, 5])
# => 3.0
```

## Implementation -- example

```ruby
NetworkX = python.import 'networkx'
# => RuBifrost::Proxy(oid=9)

graph = NetworkX.Graph()
# => RuBifrost::Proxy(oid=334)

graph.add_edges_from([
  [1, 2], [1, 3], [2, 3],
  [5, 6], [5, 8], [6, 7]
])
# => nil

NetworkX.connected_components(graph)
# => [[8, 5, 6, 7], [1, 2, 3]]
```

## Performance

How fast is matrix multiply?

+--------+-------+---------+---------+
|        | 2x2   | 128x128 | 512x512 |
+========+=======+=========+=========+
| NumPy  |  .09s |    .10s |    .28s |
+--------+-------+---------+---------+
| Ruby   |  .08s |    .79s |  45.50s |
+--------+-------+---------+---------+
| Bridge |  .19s |    .27s |   1.48s |
+--------+-------+---------+---------+

-   **NumPy** -- `numpy.dot`

-   **Ruby** -- standard library Matrix#\*

-   **Bridge** -- Bifrost from Ruby to Python, still using `numpy.dot`

# Case Study of Approaches to Finding Patterns in LED Patent Citation Networks

## Technology

-   Used Bifrost in Ruby to leverage scientific Python packages in a real-world
    case study.

-   Packages used (all Python-only):

    -   NetworkX -- graph/network library
    -   Pandas -- data transformation library
    -   MatPlotLib -- plotting/visualization library

* * * * *

```ruby
require 'rubifrost'

# Connect to the Python server.
python = RuBifrost.python

# Load graph library.
NetworkX = python.import('networkx')
# Load data library.
Pandas = python.import('pandas')
# Load visualization library.
PyPlot = python.import('matplotlib.pyplot')
```

## Questions

Given a database patents and citations between them:

-   How do we identify "important" patents?

-   Who produces these important patents -- big companies or small ones?

## Overview

A **citation network** is a **graph** representing citations between documents
such as scholarly articles or patents.

-   Each document is represented by a **node** in the graph.

-   Each citation is represented by an **edge** connecting the *citing* node to
    the *cited* node.

We used a database of LED patent citations for this study, provided by
Professor Ken Simons.

## Basic statistics

-   127,526 patents
-   327,479 citations
-   89% of patents have fewer than 5 citations
-   99% have fewer than 50 citations
-   Small group of $\approx 50$ patents with over 100 citations each

* * * * *

![Histogram of patents with under 50 citations](images/indeghist50below.pdf)

* * * * *

![Histogram of patents with 50 or more citations](images/indeghist50up.pdf)

## Cluster by neighborhoods

Most clustering techniques deal with **undirected graphs**.

For citation networks, we can use a simple **directed** clustering scheme:

-   Select a small number of highly cited patents as seeds.
-   Each seed patent defines a cluster: all patents citing the seed are
    members (its open 1-neighborhood).

* * * * *

![1-neighborhood of applnID=47614741 (444 nodes)](images/cluster1.pdf)

* * * * *

![1-neighborhood of applnID=45787627 (283 nodes)](images/cluster5.pdf)

* * * * *

![1-neighborhood of applnID=23000850 (203 nodes)](images/cluster10.pdf)

## Importance metric

Use raw citation count (indegree) or something more (i.e. PageRank)?

page_rank  indegree_rank
---------  -------------
        1              1
        2              2
        3              4
        4              5
        5            172
        6              6
        7              3
        8              8
        9              7
       10            342

## Importance metric

### Sidebar: implementation in Ruby

Ruby lacks a sparse matrix library, so the resulting 100K by 100K matrix would
take up around 10 GB of memory -- not workable on a laptop.

Bifrost lets us use Python's superior tools for this job, completing in around
1 minute -- and with only one line of code!

-   SciPy's sparse matrix implementation
-   NetworkX's already-written PageRank function

```ruby
scores = NetworkX.pagerank_scipy graph, max_iter = 200
```

## Metadata -- companies

We approximate company size with the number of patents they have in our
database.

### Top 25 companies

> `samsung` (1673), `semiconductor energy lab` (1437), `seiko` (1394), `sharp`
> (1103), `panasonic` (1094), `sony` (937), `toshiba` (848), `sanyo (tokyo
> sanyo electric)` (793), `philips` (789), `kodak` (767), `hitachi` (632),
> `osram` (631), `nec` (621), `lg` (613), `idemitsu kosan co` (553), `canon`
> (538), `pioneer` (525), `mitsubishi` (501), `rohm` (420), `tdk` (384),
> `nichia` (370), `fujifilm` (369), `ge` (363), `sumitomo` (323), `lg/philips`
> (293)

## Average citations by company

Below are the average number of citations given to each company's patents.

1. `samsung` -- 11.51
2. `semiconductor energy lab` -- 14.91
3. `seiko` -- 13.06
4. `sharp` -- 13.39
5. `panasonic` -- 13.13
6. `sony` -- 13.23
7. `toshiba` -- 14.22
8. `sanyo (tokyo sanyo electric)` -- 13.86
9. `philips` -- 14.47
10. `kodak` -- 19.98

The global average for all patents is only 5.60. Big companies *do* seem to
produce better patents.

# Conclusion

## Summary of contribution

Goal: zero-configuration cross-runtime bridge

-   No glue code

-   Works between bytecodes, runtimes, VMs, etc

Solution: dynamic RPC

-   Network protocol similar to JSON-RPC, sent over pipes

-   Backend is *automatically generated* using introspection and
    metaprogramming

-   Client library uses proxy objects to make RPC calls transparent (i.e. the
    code "looks like" regular use of the source language)

## Results

-   Bifrost protocol tested on:

    -   CRuby to CPython
    -   CPython to CPython
    -   Jython to CPython (cross-runtime)

-   Performance:

    -   Acceptable for simple calls (2x slowdown)
    -   Excellent for computation (up to 30x speedup)

## Comparison to prior art

-   Similar functionality to RubyPython when bridging from Ruby
    to Python

-   *Much* better functionality than JyNI when bridging from Jython to CPython

    -   Support for NumPy, SciPy, and many standard libaries not possible under
        JyNI

-   Different strengths than Apache Thrift

    -   Easier to use, faster to code
    -   Slower to run, less robust

# Questions
