---
title: Dynamic language bridges using remote procedure call
author: Ben Pringle

thesisdegree: Master of Science
thesisdepartment: Computer Science
thesisadviser: "Mukkai S. Krishnamoorthy"
thesissubmitdate: March 2014
thesisgraddate: May 2014

thesisacknowledgement: |
    Acknowledgement text goes here.

thesisabstract: |
    Abstract text goes here.

thesisbibliography: |
    \bibitem{thisbook} This is the first item in the Bibliography.
    Let's make it very long so it takes more than one line.
    Let's make it very long so it takes more than one line.
    \bibitem{anotherbook} The second item in the Bibliography.

thesisappendix: |
    \chapter{THIS IS AN APPENDIX}
    Note the numbering of the chapter heading is changed.
    This is a sentence to take up space and look like text.
    \section{A Section Heading}
    This is how equations are numbered in an appendix:
    \begin{equation}
    x^2 + y^2 = z^2
    \end{equation}

    \chapter{THIS IS ANOTHER APPENDIX}
    This is a sentence to take up space and look like text.

documentclass: thesis
numbersections: true
...

# INTRODUCTION

# BIFROST: A DYNAMIC REMOTE PROCEDURE CALL PROTOCOL

## `Grisbr` -- matrix multiplication proof of concept

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

The table below shows a breakdown of runtimes for native Ruby, the bridge, and
straight NumPy on matrices with various sizes:

    +--------+-------+---------+---------+
    |        | 2x2   | 128x128 | 512x512 |
    +========+=======+=========+=========+
    | Native |  .08s |    .79s |  45.50s |
    +--------+-------+---------+---------+
    | Bridge |  .19s |    .27s |   1.48s |
    +--------+-------+---------+---------+
    | Numpy  |  .09s |    .10s |    .28s |
    +--------+-------+---------+---------+

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

## `Bifrost` -- General Protocol

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
{ "result": {"__oid__": 64} }
```

Then the client can use this new object ID to call methods on that object. For
example, to request the transpose of this new matrix, simply use the proxy as a
parameter for `numpy.transpose`:

```javascript
{
    "method": "transpose",
    "oid": 42,
    "params": [ {"__oid__": 64} ]
}
```

The response will be yet *another* object proxy representing the transposed
matrix.

```javascript
{ "result": {"__oid__": 144} }
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
{ "result": {"__oid__": 42} }
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
    { "result": {"__oid__": 42} }
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
    { "result": {"__oid__": 101} }
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
            {"__oid__": 101}
        ]
    }
    ```

    Response: the final multiplied matrix in native Ruby lists

    ```javascript
    { "result": [[8, 5], [20, 13]] }
    ```
# CASE STUDY OF APPROACHES TO FINDING PATTERNS IN CITATION NETWORKS

# CONCLUSION
