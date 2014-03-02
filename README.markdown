# Dynamic language bridges using remote procedure call

Thesis by [Benjamin Pringle](http://pringley.github.io).
Advised by [Mukkai S. Krishnamoorthy](http://www.cs.rpi.edu/~moorthy).

## Build process

In order to build the thesis in PDF output format, the follow dependencies are
required:

-   `pandoc` (John Macfarlane's document converter, [pandoc](http://johnmacfarlane.net/pandoc/))
-   `pdflatex` (for example, from [TexLive](https://www.tug.org/texlive/))

The main content for the thesis is located in `main.markdown`.

To build the output (as `thesis.pdf`), simply run:

    make

## Outline of chapters

1.  **Introduction**

    Background information on langauge bridges and citation networks.

2.  **Description of Bifrost protocol**

    A simple strategy is presented for dynamically interpreting remote procedure
    calls in scripting languages, resulting in the ability to transparently use
    libraries from both languages in a single program. The protocol described
    handles complex, nested arguments and object-oriented libraries.

3.  **Case study of approaches to finding patterns in citation networks**

    Analysis of a dataset including a network of LED patents and their metadata is
    carried out using several methods in order to answer questions about the
    domain.  We are interested in finding the relationship between the metadata and
    the network structure; for example, are central patents in the network produced
    by larger or smaller companies?

4.  **Conclusion**

    Results are presented and analyzed.
