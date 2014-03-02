---
title: Dynamic language bridges using remote procedure call
author: Benjamin Pringle

thesisdegree: Master of Science
thesisdepartment: Computer Science
thesisadviser: Mukkai S. Krishnamoorthy
thesismemberone: David L. Spooner
thesismembertwo: Bülent Yener
thesissubmitdate: March 2014
thesisgraddate: May 2014

thesisacknowledgements: |
    I would like to thank:

    -   My advisor, Dr. Krishnamoorthy, for all his help and patience, and
        without whom I never would have finished this thesis.

    -   Dr. Kenneth Simons, for providing the basis of the paper and for his
        advice on its direction.

thesisabstract: |
    A simple strategy is presented for dynamically interpreting remote procedure
    calls in scripting languages, resulting in the ability to transparently use
    libraries from both languages in a single program. The protocol described
    handles complex, nested arguments and object-oriented libraries.

    We will first perform a proof-of-concept for matrix multiplication in Ruby
    (`Grisbr`), showing the performance of a manual bridge to Python very similar
    to our intended protocol.

    Then, we will present our full general protocol (`Bifrost`). Example
    implementations show two useful bridges: one between Ruby and Python, and
    another between two different Python runtimes.

    To demonstrate the robustness of `Bifrost`, it will be used in the analysis
    of a dataset including a network of LED patents and their metadata.

thesisappendix: |
    SOURCE
    ======

    This thesis was generated using John Macfarlane's Pandoc as a frontend for
    LaTeX as a renderer. Source for the thesis is available at
    <http://github.com/Pringley/masters-thesis>.

thesisbibliography: |
    \bibitem{thisbook} This is the first item in the Bibliography.
    Let's make it very long so it takes more than one line.
    Let's make it very long so it takes more than one line.
    \bibitem{anotherbook} The second item in the Bibliography.

documentclass: thesis
numbersections: true
links-as-notes: true
classoption: [chap]
...

INTRODUCTION
============

A **language bridge** allows a program written in one language to use functions
or libraries from a different language. For example, a web server written in
Ruby might use a bridge to call backend functions written in Java.

The use of languages bridges often introduces significant overhead, either in
performance or in code complexity. However, if the destination language is
faster or has better libraries, the benefits often outweigh those costs.

## Existing techniques

The concept of a language bridge is not a new one. Current techniques vary in
overhead and complexity.

### Common Intermediate Language

Languages within the same runtime are typically capable of bridging with little
to no overhead.

This is the approach used by Microsoft's .NET framework to provide language
interoperability between C#, C++, Visual Basic, and others. All code is
compiled to a common intermediate language, a shared bytecode executed by a
virtual machine.

The Java ecosystem can also be used similarly -- for example, between Jython
and Java programs.

### Foreign Function Interface

For languages with a common link to C, the Foreign Function Interface is a
powerful tool for passing types across a bridge.

RubyPython uses FFI to dynamically generate a bridge between the C
implementation of Ruby and CPython.

This is an excellent approach but quickly becomes difficult when bridging
across runtimes. For example, Java uses JNI (Java Native Interface) for foreign
function calls to C. Prior art exists trying to connect Jython and CPython, but
the restriction on types makes things difficult. Many standard libraries are
not functional, and NumPy also does not work using this technique.

### Remote Procedure Call

The most robust technique for language bridging is remote procedure call --
send requests through a channel to a server running the other language.

Excellent frameworks exist such as Apache Thrift (used extensively by
Facebook). However, these require extensive configuration for each function
that needs bridging:

```
struct UserProfile {
    1: i32 uid,
    2: string name,
    3: string blurb
}
service UserStorage {
    void store(1: UserProfile user),
    UserProfile retrieve(1: i32 uid)
}
```

## Desired features

In order to achieve the best of both worlds, we need:

-   **Cross-runtime**: we may want to use libraries that are compiled in
    different bytecodes -- for example, mix Java and C libraries

-   **Dynamic**: generate the bindings for *any* library without tedious "glue
    code" like Thrift

We aim to do this by using:

-   **Remote procedure call** over UNIX pipes to cross runtimes
-   **Language introspection** to eschew configuration files

The next chapter demonstrates our technique.

BIFROST: A DYNAMIC REMOTE PROCEDURE CALL PROTOCOL
=================================================

Section \ref{grisbersec} presents a proof of concept called `Grisbr`, a Ruby
library that performs matrix multiplication by sending requests to a Python
server. This demonstrates the first part of the scheme -- the remote procedure
call using JSON over UNIX pipes. We evaluate the performance of this technique
for multiplication of large and small matrices.

Section \ref{bifrostsec} presents `Bifrost`, a generalized version of `Grisbr`
that can load any module or package, generally handle most functions, and even
use foreign language objects in the client space.

## `Grisbr` -- matrix multiplication proof of concept {#grisbersec}

In Ruby, matrix multiplication is done via the
[Matrix#*](http://www.ruby-doc.org/stdlib-2.0.0/libdoc/matrix/rdoc/Matrix.html#method-i-2A)
method:

```ruby
require 'matrix'
a = Matrix[[1, 2], [3, 4]]
b = Matrix[[4, 3], [2, 1]]
puts a * b
# => Matrix[[8, 5], [20, 13]]
```

This works for small matrices, but since it is implemented in pure Ruby, it can
be very slow. For example, multiplying 512x512 matrices takes over 45 seconds
on a consumer laptop:

    $ cd ruby
    $ time ruby mm-native.rb ../inputs/512.txt
    ruby mm-native.rb ../inputs/512.txt  45.45s user 0.04s system 99% cpu 45.502 total

To speed this up, we could write the function in C, which Ruby supports, but
this is both tedious and error-prone.

Ruby has a fast *and* high-level matrix implementation in the works -- it's
called [NMatrix](http://sciruby.com/nmatrix/) from
[SciRuby](http://sciruby.com/). Unfortunately, this is still alpha software.

On the other hand, Python has [NumPy](http://www.numpy.org/), which is both
stable and feature-rich.

This proof-of-concept shows that the use of a Ruby-to-Python bridge is a
feasible method for matrix multiplication. The bridge uses
[JSON](http://www.json.org/)-encoded calls over POSIX pipes for communication
between the Ruby process and a forked Python process.

Our example demonstrates a 30x speedup from native Ruby, reducing the runtime
on the 512 by 512 down to just a second and a half:

    $ time ruby mm-grisbr.rb ../inputs/512.txt
    ruby mm-grisbr.rb ../inputs/512.txt  1.32s user 0.18s system 101% cpu 1.480 total

### Implementation Overview

The Ruby side of the bridge encodes a request as a JSON string with named
arguments. Ruby then forks a Python process with the Python receiver code and
sents the JSON request to the Python process's standard input pipe. After
blocking on computation, Ruby receives the JSON-encoded result back from the
Python process's standard output pipe. This result is then decoded and returned
to the main program.

```ruby
require 'open3'

module Grisbr
  def self.multiply a, b
    # Convert arguments to JSON.
    args = JSON.generate({a: a, b: b})

    # Fork a process running the Python receiver server, sending the function
    # parameters via stdin.
    result, status = Open3.capture2("python grisbr-receiver.py",
                                    stdin_data: args)
    # Parse the response JSON and return.
    JSON.parse(result)["c"]
  end
end
```

On the Python side, the JSON-encoded is read on standard input. The arguments
are transformed into NumPy arrays, multiplied, then printed back to standard
output in JSON form.

```python
from json import loads, dumps
from numpy import array, dot
from sys import stdin, stdout

# Load request JSON from stdin.
args = loads(stdin.read())

# Convert to NumPy types and multiply matrices.
a, b = map(array, (args['a'], args['b']))
c = dot(a, b)

# Encode the result in JSON and write to stdout.
result = dumps({'c': c.tolist()})
stdout.write(result)
stdout.flush()
```

The bridge is transparent to the library user, who simply uses the `Grisbr`
module:

```ruby
# From Ruby
require 'grisbr'
a = [[1, 2], [3, 4]]
b = [[4, 3], [2, 1]]
p Grisbr.multiply(a, b)
# => [[8, 5], [20, 13]]
```

### Results for `Grisbr`

Table \ref{grisbrruntime} shows a breakdown of runtimes for native Ruby, the
bridge, and straight NumPy on matrices with various sizes:

+--------+-------+---------+---------+
|        | 2x2   | 128x128 | 512x512 |
+========+=======+=========+=========+
| Ruby   |  .08s |    .79s |  45.50s |
+--------+-------+---------+---------+
| Grisbr |  .19s |    .27s |   1.48s |
+--------+-------+---------+---------+
| Python |  .09s |    .10s |    .28s |
+--------+-------+---------+---------+

Table: Run time comparison for matrix multiplication with `Grisbr`
\label{grisbrruntime}

On the 512 by 512 matrix, we saw a 30x speedup using the bridge!

However, on that same matrix, the bridge is still 6 times slower than just
using straight numpy.

Also, the time spent marshalling JSON data between processes is wasted. This
means on smaller matricies, native Ruby beats the bridge.

The next chapter presents `Bifrost`, which builds on the success of this one,
generalizing the bridging technique in two ways:

-   Use **dynamic introspection** to automatically support (almost) any
    library, rather than hard-coding the request server.

-   Use **object proxies** to allow for intermediate results.

## `Bifrost` -- General Protocol {#bifrostsec}

Our full protocol will take the result from `Grisbr` and combine it with
introspection and object proxies for a general solution.

### JSON over IPC

The basic idea remains the same. The client will create a subprocess running a
server in the destination language which will receive requests over JSON.

The protocol is inspired by [JSON-RPC](http://json-rpc.org/), but it is not
compatible. (Changes were made to fit the requirements of this project.)

For example, to request `numpy.mean`, a NumPy function to calculate the mean of
an array of numbers from 1 to 4, the request might look like:

```javascript
{
    "method": "mean",
    "oid": 42,
    "params": [ [1, 2, 3, 4] ]
}
```

The request has three fields:

-   **`method`** is the name of the method to call.

-   **`oid`** is the identifier for the destination-language object that
    contains the method. In this case, `42` is the object ID (`oid`) for NumPy.
    (More on object IDs in the upcoming section on object proxies.)

-   **`params`** is an array of parameters for the method. In this case, there
    is only one parameter, the array of numbers that we want the mean for
    (`[1, 2, 3, 4]`).

The subprocess server receives this request on standard input, processes it,
and responds on standard output:

```javascript
{ "result": 2.5 }
```

The protocol also handles basic error reporting. For example, if a non-existing
method is requested:

```javascript
{
    "method": "asdfasdfasdf",
    "oid": 42,
    "params": []
}
```

The server should notice the error and respond with a message:

```javascript
{ "error": "method \"asdfasdfasdf\" does not exist" }
```

#### Non-string dictionary keys

In JSON, all dictionary keys *must* be strings. However, many libraries use
dictionaries to map non-string objects -- for example, to create a Graph using
the NetworkX library for Python, one would write something like this:

```python
networkx.DiGraph({1: [2, 4], 2: [3]})
```

The dictionary is an adjacency list for a directed (one-way) graph -- node 1 is
adjacent to 2 and 4; node 2 is adjacent to 3.

This is a simple and common use case, but if we want to request this function
call over our protocol, **we couldn't use a native JSON dictionary to represent
this, since the keys are not strings!**

Instead, we will define an alternative (and optional) syntax for dictionaries
with non-string keys. Instead of using a mapping type to represent the
dictionary, just use a list of lists with a special wrapper:

```javascript
/* naive way -- INVALID JAVASCRIPT */
{1: 2, 3: 4}

/* BiFrost way -- marked list of lists */
{"__bf_dict__": [[1, 2], [3, 4]]}
```

For example, the NetworkX call would be represented as:

```javascript
{
    "method": "DiGraph",
    "oid": 9,
    "params": {"__bf_dict__": [[1, [2, 4]], [2, [3]]]}
}
```

### Dynamic introspection

The `Grisbr` implementation hard-coded the server's reaction to a response --
instead, we will dynamically call a function based on the request.

Scripting languages typically have some form of introspection or
metaprogramming. In Python, the relevant function is the builtin `getattr`.
From the Python 3.3.4 documentation:

> **getattr**(*object*, *name*[, *default*])
>
> > Return the value of the named attribute of object. name must be a string.
> > If the string is the name of one of the object’s attributes, the result is
> > the value of that attribute. For example, getattr(x, 'foobar') is
> > equivalent to x.foobar. If the named attribute does not exist, default is
> > returned if provided, otherwise AttributeError is raised.

A Python server can use this to dynamically call a requested function. The
implementation might look something like this (ignoring any error processing
and other details):

```python
def handle(request_json):
    # Extract information from request.
    request = json.loads(request_json)
    parameter_list = request['params']
    method_name = request['method']
    object_id = request['oid']

    # Look up object via ID from internal table.
    obj = object_table[object_id]

    # Use python's introspective `getattr` to look up the method name.
    method = getattr(obj, method_name)

    # Call the method with the supplied parameters and return the result.
    result = method(*parameter_list)
    return result
```

### Object Proxies

Most libraries for modern scripting languages are more than just a flat module
of functions -- they make heavy use of objects, both to store state and to
group methods. This causes an issue for typical remote procedure call schemes
that assume the flat module paradigm.

In order to handle this, we assign each object stored on the server a unique
identifer called its `oid` (object ID).

For example, to create a NumPy n-dimensional array object, one could send the
following request:

```javascript
{
    "method": "ndarray",
    "oid": 42,
    "params": [ [[1, 2], [3, 4]] ]
}
```

This returns an **object proxy** -- essentially just an empty container with
the object ID it represents.

```javascript
{ "result": {"__bf_oid__": 64} }
```

Then the client can use this new object ID to call methods on that object. For
example, to request the transpose of this new matrix, simply use the proxy as a
parameter for `numpy.transpose`:

```javascript
{
    "method": "transpose",
    "oid": 42,
    "params": [ {"__bf_oid__": 64} ]
}
```

The response will be yet *another* object proxy representing the transposed
matrix.

```javascript
{ "result": {"__bf_oid__": 144} }
```

To actually view the transposed matrix, we can call the `ndarray.tolist()`
function on the object proxy itself (#144, the transposed matrix):

```javascript
{
    "method": "tolist",
    "oid": 144,
    "params": []
}
```

The response will be our transposed matrix in native list types:

```javascript
{ "result": [[1, 3], [2, 4]] }
```

#### Implementation

In order to implement transparent object proxies, metaprogramming comes to the
rescue once again. This time, it's Ruby's method\_missing:

> **method\_missing(symbol[, \*args]) -> result**
>
> Invoked by Ruby when obj is sent a message it cannot handle. symbol is the
> symbol for the method called, and args are any arguments that were passed to
> it. By default, the interpreter raises an error when this method is called.
> However, it is possible to override the method to provide more dynamic
> behavior.

We can create a proxy object by overriding method\_missing to pass the request
down to the server for the other language. A simplified example is shown below:

```ruby
class RuBifrost::Proxy
  attr_reader :oid
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

The proxy approach even generalizes nicely to modules themselves. We define a
new message used to request a module:

```javascript
{ "module": "numpy" }
```

The response is then simply an object proxy representing the module.

```javascript
{ "result": {"__bf_oid__": 42} }
```

This elegantly solves any namespacing issues between modules without any
additional code.

### Full protocol example -- matrix multiplication

The following exchange shows importing the `numpy` module, multiplying two
matrices, and retrieving the result from the returned object proxy.

1.  **Import the module**

    Request: ask for the module to be loaded

    ```javascript
    { "module": "numpy" }
    ```

    Response: an object proxy representing the module

    ```javascript
    { "result": {"__bf_oid__": 42} }
    ```

2.  **Multiply the matrices.**

    Request: supply to matrices for multiplication by NumPy

    ```javascript
    {
        "method": "dot",
        "oid": 42,
        "params": [
            [[1, 2], [3, 4]],
            [[4, 3], [2, 1]]
        ]
    }
    ```

    Response: an object proxy representing the result of the matrix
    multiplication

    ```javascript
    { "result": {"__bf_oid__": 101} }
    ```

3.  **Extract native types from object proxy**

    Since `numpy.dot` returns a `numpy.ndarray` instead of a native array of
    arrays, we need to use `numpy.ndarray.tolist()` to get those native types.

    Request: the list-of-lists versions of the final matrix

    ```javascript
    {
        "method": "tolist",
        "oid": 101,
        "params": [
            {"__bf_oid__": 101}
        ]
    }
    ```

    Response: the final multiplied matrix in native Ruby lists

    ```javascript
    { "result": [[8, 5], [20, 13]] }
    ```

CASE STUDY OF APPROACHES TO FINDING PATTERNS IN CITATION NETWORKS
=================================================================

## Background

A **citation network** is a **graph** representing citations between documents
such as scholarly articles or patents. Each document is represented by a
**node** in the graph, and each citation is represented by an **edge**
connecting the *citing* node to the *cited* node.

Earlier work in the area of citation network analysis by @garfield64
popularized the systematic use of forward citation count as a metric for
scholarly influence. @hummon89 defined several new metrics to track paths of
influence, which were later improved by @batagelj03.  The PageRank algorithm
was introduced by @page99rank. It originally powered the Google search engine,
treating hypertext links as "citations" between documents on the world wide
web. These are merely a select few prior works -- this listing fails to exhaust
even the highlights.

### Case study: LED patents

In this paper, we will be using a network of roughly one hundred thousand LED
patent applications supplied by @simons11data.

All data is stored in plain `latin-1`-encoded text, with one row of data per
line of text, and fields separated by tab characters.

Each patent application has a unique identifier: `applnID`.

The dataset includes a list of all citations (mapping the citing `applnID` to
the cited `applnID`), in addition to several metadata fields:

-   `appMyName` -- normalized name of company applying for patent

#### A very brief history of LED patents

@partridge76 filed the first patent demonstrating electroluminescence from
polymer films, one of the key advances that lead to the development of organic
LEDs. (This is `applnID` 47614741 in our dataset.)

Kodak researchers @vanslyke85 built on this work when they filed a new patent
demonstrating improved power conversion in organic electroluminescent devices.
(This is `applnID` 51204521 in our dataset.) Another group of Kodak scientists,
@tang88, patented the first organic LED device, now used in televisions,
monitors, and phones.

This background helps to validate our methods for classifying patents as
"important." A good algorithm should classify the 47614741 and 51204521 nodes
as significant. When we present our techniques, we will use this as one metric
of success.

### Computation

The computation for our analysis was performed using the Python programming
language (<http://python.org/>) and the following libraries:

-   `networkx` for network representation and analysis [@hagberg08]
-   `pandas` for tabular data analysis [@mckinney12]
-   `scipy` for statistics [@jones01]
-   `matplotlib` for creating plots [@hunter07]

More information about the code written for this paper can be found under the
section, [Code](#code).

## Approaches

### Network structure

The graph has 127,526 nodes and 327,479 edges.

#### Forward citations (indegree)

![Histogram of patents with under 50 citations](images/indeghist50below.pdf)

![Histogram of patents with 50 or more citations](images/indeghist50up.pdf)

Popularized by @garfield64, the simplest way to determine a patent's relative
importance is counting its forward citations -- that is, other patents which
cite the patent in question. In a citation network where edges are drawn from
the citing patent to the cited patent, the number of forward citations for a
given node is its **indegree**, or the number of edges ending at the given
node.

In our data, 89% of patents have fewer than 5 citations, and 99% have fewer
than 50. Nevertheless, there is a small group of slightly over fifty patents
with at least a hundred citations each.

The top ten most-cited patents in our dataset are shown in Table
\ref{topindegree}.

 applnID  indegree
-------- ---------
47614741       444
51204521       360
52376694       339
48351911       305
45787627       283
45787665       267
46666643       235
53608703       213
54068562       213
23000850       203

Table: Top ten most-cited patents
\label{topindegree}

##### Computation

We computed indegree using `networkx.DiGraph.in_degree()` [@hagberg08].

#### PageRank

Another technique for classifying important nodes in a graph is PageRank
[@page99rank], a famous algorithm used by the Google search engine to rank web
pages.

PageRank calculates the probability that someone randomly following citations
will arrive at a given patent. The damping factor $d$ represents the
probability at each step that the reader will continue on to the next patent.

For each patent in our dataset, we calculated:

-   `pagescore` -- raw PageRank score (probability 0 to 1)
-   `page_rank` -- relative numerical rank of the patent (by PageRank)
-   `indegree` -- number of forward citations
-   `indegree_rank` -- relative numerical rank of the patent (by indegree)

Table \ref{toppagerank} shows the top ten patents sorted by PageRank.

 applnID  pagescore  page_rank  indegree  indegree_rank
--------  ---------  ---------  --------  -------------
47614741   0.000371          1       444              1
51204521   0.000329          2       360              2
48351911   0.000291          3       305              4
45787627   0.000241          4       283              5
48112868   0.000227          5        63            172
45787665   0.000220          6       267              6
52376694   0.000210          7       339              3
53608703   0.000193          8       213              8
46666643   0.000173          9       235              7
47823143   0.000168         10        47            342

Table: Top ten patents by PageRank
\label{toppagerank}

Within our dataset, PageRank and indegree are correlated with a Pearson
product-moment coefficient of $r=.80$.

##### Computation

We computed PageRank using `networkx.pagerank_scipy()` with `max_iter` set to
200 and a damping factor of $d=.85$ [@page99rank; @hagberg08].

### Clustering

![Neighborhood sizes for top 20 cited patents](images/nhood_sizes.pdf)

As noted by @satuluri11, most clustering techniques deal with undirected
graphs.  We introduce a very simple technique for defining overlapping
clusters in a *directed* citation network:

-   Select a small number of highly cited patents as seeds.
-   Each seed patent defines a cluster: all patents citing the seed are
    members (its open 1-neighborhood).

We considered using larger neighborhoods. The $n$-neighborhood can be computed
recursively by adding all patents citing any patents in the
$(n-1)$-neighborhood. However, these larger neighborhoods grow in size very
quickly. For our purposes of quick computation and visualization, we chose to
keep the smaller clusters from 1-neighborhoods.

This technique creates *overlapping* clusters, where a node can belong to more
than one cluster. Looking at the clusters created from the top 10 most-cited
patents, we computed two measures of overlapping:

-   `percentunique` is the fraction of nodes in *only* that cluster
-   `bignodes` is the number of seed nodes that appear in the cluster (for
    example, the  second cluster contains the seed patent used to generate the
    first cluster, along with three others from our original ten seeds)

Table \ref{clusteruniqueness} shows the value of `percentunique` and `bignodes`
for each of the ten clusters:

 clustersize  percentunique  bignodes
------------ -------------- ---------
         444       0.202703         0
         360       0.100000         4
         339       0.280236         0
         305       0.163934         4
         283       0.141343         0
         267       0.101124         0
         235       0.940426         0
         213       0.985915         0
         213       0.464789         0
         203       0.226601         0

Table: Uniqueness measures for clusters of patents
\label{clusteruniqueness}

Looking at `percentunique`, many clusters have a good deal over overlap, with
unique contributions as low as 10%, although others are up to 98% unique. Our
analysis will therefore **not** assume that these clusters strictly partition
the data, and rather look at the clusters as distinct but potentially
overlapping areas of patents.

![1-neighborhood of applnID=47614741 (444 nodes)](images/cluster1.pdf)

![1-neighborhood of applnID=45787627 (283 nodes)](images/cluster5.pdf)

![1-neighborhood of applnID=23000850 (203 nodes)](images/cluster10.pdf)

##### Computation

The $n$-neighborhood of a node can be computed using the [included
code](#code):

```python
neighborhood(graph, nbunch, depth=1, closed=False)
```

-   `graph` -- a `networkx.DiGraph` [see @hagberg08]
-   `nbunch` -- a node or nodes in `graph`
-   `depth` -- the number of iterations (defaults to 1-neighborhood)
-   `closed` -- set to `True` if the neighborhood should include the root

Returns a `set` containing the neighborhood of the node, or a `dict` matching
nodes to neighborhood `set`s.

### Metadata analytics

Note that only about 35% of the patents in our dataset (44356 out of 127526)
were supplied with `appMyName` (company name).

#### Choosing a metric for company size

We would like to explore whether company size has any correlation with patent
quality.  Do major innovations originate from big labs, or do smaller companies
pave the way (only to be later acquired)?

In order to begin this investigation, we need a solid metric to quantify
"company size." Our first thought was to use a metadata-based solution, such as
the company's net worth or number of employees. However, it wasn't clear at
*which point in time* to measure the company size -- does a company's employee
count in 2013 affect the quality of a patent it filed in the 1980s?

Instead, we choose a simple metric contained within our dataset: company size
is defined as the **number of patents submitted**.

This may not be a perfect representation of "size," but it still allows us to
analyze whether these "prolific" companies are contributing any *important*
patents or merely a large volume of consequential patents.

Our set of "large companies" will therefore be the 25 companies that applied
for the largest number of patents. They are, in order with number of LED
patents each:

> `samsung` (1673), `semiconductor energy lab` (1437), `seiko` (1394), `sharp`
> (1103), `panasonic` (1094), `sony` (937), `toshiba` (848), `sanyo (tokyo
> sanyo electric)` (793), `philips` (789), `kodak` (767), `hitachi` (632),
> `osram` (631), `nec` (621), `lg` (613), `idemitsu kosan co` (553), `canon`
> (538), `pioneer` (525), `mitsubishi` (501), `rohm` (420), `tdk` (384),
> `nichia` (370), `fujifilm` (369), `ge` (363), `sumitomo` (323), `lg/philips`
> (293)

#### Summed outdegree

The "summed score" metric isn't very useful in this situation, since we've
already ranked our patents by frequency in our definition of company size. The
summed score for outdegree gives us little new information.

Below is our list of top 25 patents, with their relative ranking by summed
outdegree score in parentheses:

> `samsung` (2), `semiconductor energy lab` (1), `seiko` (3), `sharp` (5),
> `panasonic` (6), `sony` (7), `toshiba` (8), `sanyo (tokyo sanyo electric)`
> (10), `philips` (9), `kodak` (4), `hitachi` (15), `osram` (14), `nec` (11),
> `lg` (17), `idemitsu kosan co` (12), `canon` (16), `pioneer` (13),
> `mitsubishi` (18), `rohm` (22), `tdk` (20), `nichia` (19), `fujifilm` (25),
> `ge` (21), `sumitomo` (26), `lg/philips` (27)

As expected, our top-frequency companies have very high rankings by summed
outdegree score.

#### Normalized summed outdegree

Instead, we can look at the *normalized* outdegree, or the mean outdegree of a
patent produced by one of our companies. Let's take a look at just our top 10
companies:

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

By comparison, the mean outdegree over *all* patents is 5.60.

#### Contribution factor -- outdegree

Let us define patents as relatively significant if their outdegree is in the
75th percentile. (For our LED dataset, this includes all patents with at least
11 citations.)

Then, we can calculate contribution factors for each company by finding the
fraction of their patents that are considered relatively significant. Here are
the results:

1. `samsung` -- .63
2. `semiconductor energy lab` -- .85
3. `seiko` -- .78
4. `sharp` -- .86
5. `panasonic` -- .85
6. `sony` -- .82
7. `toshiba` -- .89
8. `sanyo (tokyo sanyo electric)` -- .88
9. `philips` -- .76
10. `kodak` -- .84

#### Date partitioning

Another interesting approach is to look at the filing date of the patents.
Table \ref{patentdatehist} histogram of number of patents by filing date.

date range	                count
-------------------------   ------
1940-11-12 to 1945-07-06	1
1945-07-06 to 1950-02-28	6
1950-02-28 to 1954-10-23	107
1954-10-23 to 1959-06-17	247
1959-06-17 to 1964-02-09	369
1964-02-09 to 1968-10-03	344
1968-10-03 to 1973-05-28	362
1973-05-28 to 1978-01-20	575
1978-01-20 to 1982-09-14	678
1982-09-14 to 1987-05-09	1125
1987-05-09 to 1992-01-01	2257
1992-01-01 to 1996-08-25	3451
1996-08-25 to 2001-04-19	8103
2001-04-19 to 2005-12-12	16019
2005-12-12 to 2010-08-06	5040

Table: Histogram of patents by filing date.
\label{patentdatehist}

We can partition each company's patents into thirds -- that is, `samsung0`
contains the first chronological third of Samsung's patents, `samsung1`
contains the second third, and `samsung2` contains the final third.

We can calculate normalized outdegree for each third, shown in Table
\ref{normoutdegbydatepart}.

company    partition  start       end         normalizedoutdeg    count  totalcount
--------   ---------  ----------- ----------- ------------------  ------ ----------
samsung    0          1989-05-30  2004-06-28  2.6858168761220824  557    1673
samsung    1          2004-06-28  2005-11-30  1.3375224416517055  557    1673
samsung    2          2005-12-02  2010-07-13  0.5116279069767442  559    1673
sel        0          1982-02-09  2002-02-26  8.187891440501044   479    1437
sel        1          2002-02-28  2004-06-23  5.1941544885177455  479    1437
sel        2          2004-06-25  2010-01-06  1.3528183716075157  479    1437
seiko      0          1973-07-13  2002-02-22  5.644396551724138   464    1394
seiko      1          2002-02-25  2004-01-21  2.543103448275862   464    1394
seiko      2          2004-01-21  2009-06-18  0.9978540772532188  466    1394
sharp      0          1972-07-31  1994-02-22  4.809264305177112   367    1103
sharp      1          1994-02-25  2001-10-29  3.5476839237057223  367    1103
sharp      2          2001-10-31  2010-02-26  1.8130081300813008  369    1103
panasonic  0          1963-11-18  1997-10-31  3.4148351648351647  364    1094
panasonic  1          1997-11-05  2002-02-21  3.6950549450549453  364    1094
panasonic  2          2002-02-27  2010-03-05  2.2868852459016393  366    1094
sony       0          1970-04-13  2000-09-11  4.064102564102564   312    937
sony       1          2000-09-14  2003-08-20  4.0576923076923075  312    937
sony       2          2003-08-28  2010-02-10  1.5878594249201279  313    937
toshiba    0          1969-08-25  1993-03-30  4.184397163120567   282    848
toshiba    1          1993-04-13  2001-04-27  6.1063829787234045  282    848
toshiba    2          2001-04-27  2010-03-23  2.3732394366197185  284    848
sanyo      0          1976-12-09  2000-03-17  6.943181818181818   264    793
sanyo      1          2000-03-17  2003-03-28  3.25                264    793
sanyo      2          2003-03-28  2009-01-15  1.4037735849056603  265    793
philips    0          1954-01-29  1999-09-08  6.011406844106464   263    789
philips    1          1999-09-08  2004-07-01  6.068441064638783   263    789
philips    2          2004-07-09  2009-06-03  1.326996197718631   263    789
kodak      0          1965-03-25  2001-01-30  23.63529411764706   255    767
kodak      1          2001-02-02  2003-09-23  4.670588235294118   255    767
kodak      2          2003-09-24  2008-02-25  1.7042801556420233  257    767

Table: Normalized outdegree for date partitions
\label{normoutdegbydatepart}

## Results

Based on our meta-metrics, it appears that while large companies file many patent
applications, these patents are *not* of any lower quality than average.

By the normalized summed outdegree measure, the top 10 companies each had a
mean outdegree more than *double* that of the entire dataset.

By contribution factor analysis, each of the top 10 (except Samsung) still
exceeded the expected ratio.

CONCLUSION
==========
