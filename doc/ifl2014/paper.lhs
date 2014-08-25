\documentclass[preprint,authoryear]{sigplanconf}

\usepackage{amsmath}

\include{definitions}

%include lambda.fmt
%include polycode.fmt
%subst conid a = "\mathsf{" a "}"
%subst varid a = "\mathsf{" a "}"
%format a = "\mathit{a}"
%format b = "\mathit{b}"
%format s = "\mathit{s}"
% UGLY HACK: we abuse string literals to denote quasiquotes.
%subst string txt = "\llbracket \mathsf{r}|\texttt{\;" txt "\;}\rrbracket"

\begin{document}

\conferenceinfo{IFL'14}{October 1--3, 2014, Boston, MA, USA}
\copyrightyear{2014}

\exclusivelicense

\title{Project H: Programming R in Haskell}
\subtitle{(Extended Abstract)}

\authorinfo{Name1}
           {Affiliation1}
           {Email1}
\authorinfo{Name2\and Name3}
           {Affiliation2/3}
           {Email2/3}

\maketitle

\begin{abstract}
  A standard method for augmenting the ``native'' set of libraries
  available within any given programming environment is to extend this
  set via a foreign function interface provided by the programming
  language. In this way, by exporting the functionality of external
  libraries via {\em binding modules}, one is able to reuse libraries
  without having to reimplement them in the language {\em du jour}.

  However, {\em a priori} bindings of entire system libraries is
  a tedious process that quickly creates an unbearable maintenance
  burden. We demonstrate an alternative to monolithic and imposing
  binding modules, be it to make use of libraries implemented in
  a special-purpose, dynamically typed, interpreted language. As
  a case study, we present \SysH, an R-to-Haskell interoperability
  solution making it possible to program all of R, including all
  library packages on CRAN, from Haskell, a general-purpose,
  statically typed, compiled language. We demonstrate how to do so
  efficiently, without marshalling costs when crossing language
  boundaries and with static guarantees of well-formation of
  expressions and safe acquisition of foreign language resources.
\end{abstract}

%\category{CR-number}{subcategory}{third-level}

\keywords R, Haskell, foreign function interface, quasiquotation,
language embedding, memory regions

\section{Introduction}
  
The success or failure in the industry of a programming language
within a particular problem domain is often predicated upon the
availability of a sufficiently plethoric set of good quality libraries
relevant to the domain. Libraries enable code reuse, which ultimately
leads to shorter development cycles. Yet business and regulatory
constraints may impose orthogonal requirements that not all
programming languages are able to satisfy.

Case in point: at Amgen, we operate within a stringent regulatory
environment that requires us to establish high confidence as to the
correctness of the software that we create. In life sciences, it is
crucial that we aggressively minimize the risk that any bug in our
code, which could lead to numerical, logical or modelling errors with
tragic consequences, goes undetected.

TODO more about the needs of Amgen and why it uses Haskell.

TODO more about the needs of Amgen and why it needs R.

%% R is a free software environment for statistical computing and
%% graphics. It includes a full blown programming language for
%% exploratory programming and statistics.

We present a method to make available any foreign library without the
overheads typically associated with more traditional approaches. Our
goal is to allow for the seamless integration of R with Haskell ---
invoking R functions on Haskell data and {\em vice versa}.

\paragraph{Foreign Function Interfaces} The complexity of modern
software environments makes it all but essential to interoperate
software components implemented in different programming languages.
Most high-level programming languages today include a {\em foreign
  function interface (FFI)}, which allows interfacing with lower-level
programming languages to get access to existing system and/or
purpose-specific libraries (TODO refs). An FFI allows the programmer
to give enough information to the compiler of the host language to
figure out how to {\em invoke} a foreign function included as part of
a foreign library, and how to {\em marshal} arguments to the function
in a form that the foreign function expects. This information is
typically given as a set of bindings, one for each function, as in the
example below:
%% newtype ClockId = ClockId Int32
%%
%% instance Storable TimeSpec where
%%   sizeOf _ = 12
%%   alignment _ = 4
%%   peek ptr = do
%%       ss <- peekByteOff ptr 0
%%       ns <- peekByteOff ptr 8
%%       return $ TimeSpec ss ns
%%   poke ptr (TimeSpec ss ns) = do
%%       pokeByteOff ptr 0 ss
%%       pokeByteOff ptr 0 ns

%format INCLUDE_TIME_H = "\texttt{\#include <time.h>}"
%format CLOCK_GETTIME = "\char34" clock_gettime "\char34"
%format GETTIME = "\char34" getTime "\char34"
%format cid = "\mathit{cid}"
%format ts = "\mathit{ts}"
%format foreign = "\mathbf{foreign}"
%format ccall = "\mathbf{ccall}"
\begin{code}
{-# LANGUAGE ForeignFunctionInterface #-}
module Example1 (getTime) where
import Foreign
import Foreign.C

INCLUDE_TIME_H

data TimeSpec = TimeSpec
  { seconds      :: Int64
  , nanoseconds  :: Int32
  }

foreign import ccall CLOCK_GETTIME
  c_clock_gettime :: ClockId -> Ptr TimeSpec -> IO CInt

getTime :: ClockId -> IO TimeSpec
getTime cid = alloca $ \ts -> do
    throwErrnoIfMinus1_ GETTIME $
      c_clock_gettime cid ts
    peek ts
\end{code}
In the above, |c_clock_gettime| is a binding to the
\verb|clock_gettime()| C function. The API conventions of C functions
are often quite different from that of the host language, so that it
is convenient to export the wrapper function |getTime| rather than the
binding directly. The wrapper function takes care of converting from
C representations of arguments to values of user defined data types
(performed by the |peek| function, not shown), as well as mapping any
foreign language error condition to a host language exception.

\paragraph{Binding generators} These bindings are tedious and error prone to write, verbose, hard to
read and a pain to maintain as the API of the underlying library
shifts over time. To ease the pain, over the years, {\em binding
  generators} have appeared (TODO ref), in the form of pre-processors
that can parse C header files and automate the construction of binding
wrapper functions and argument marshalling. However, these tools:
\begin{enumerate}
\item do not alleviate the programmer from the need to repeat in the
  host language the type of the foreign function;
\item add yet more complexity to the compilation pipeline;
\item being textual pre-processors, generate code that is hard to
  debug;
\item are necessarily limited in terms of the fragments of the source
  language they understand and the types they can handle, or repeat
  the complexity of the compiler to parse the source code.
\end{enumerate}
Point (1) above is particularly problematic, because function
signatures in many foreign libraries have a knack for evolving over
time, meaning that bindings invariably lag behind the upstream foreign
libraries in terms of both the versions they support, and the number
of functions they bind to.

Moreover, such binding generators are language specific, since they
rely on intimate knowledge of the foreign language in which the
foreign functions are available. In our case, the foreign language is
R, which none of the existing binding generators support. We would
have to implement our own binding generator to alleviate some of the
burden of working with an FFI. But even with such a tool in hand, the
tedium of writing bindings for all standard library functions of R,
let alone all functions in all CRAN packages, is but a mildly exciting
prospect. One would need to define a monolithic set of bindings
(i.e.\ a {\em binding module}), for {\em each} R package. Because we
cannot anticipate exactly which functions a user will need, we would
have little recourse but to make these bindings as exhaustive as
possible.

Rather than {\em bind} all of R, the alternative is to {\em embed} all
of R. Noting that GHC flavoured Haskell is a capable meta-programming
environment, the idea is to define code generators which, at each call
site, generates code to invoke the right R function and pass arguments
to it using the calling convention that it expects. In this way, there
is no need for {\em a priori} bindings to all functions. Instead, it
is the code generator that produces code spelling out to the compiler
exactly how to perform the R function call -- no binding necessary.

It just so happens that the source language for these code generators
is R itself. In this way, users of H may express invocation of an
R function using the full set of syntactical conveniences that
R provides (named arguments, variadic functions, {\em etc.}), or
indeed write arbitrary R expressions. R has its own equivalent to
\verb|clock_gettime()|, called \verb|Sys.time()|. With an embedding of
R in this fashion, calling it is as simple as:
%format GREETING = "\texttt{\char34 The current time is:\;\char34}"
%format now = "\mathit{now}"
\begin{code}
printCurrentTime = do
    now <- "Sys.time()"
    putStrLn (GREETING ++ fromSEXP now)
\end{code}
The key syntactical device here is {\em quasiquotes} (TODO ref), which
allow mixing code fragments with different syntax in the same source
file --- anything within an |"..."| pair of brackets is to be
understood as R syntax.

\paragraph{Contributions} In this paper, we advocate for a novel
approach to programming with foreign libraries, and illustrate this
approach with the first complete, high-performance tool to access all
of R from a statically typed, compiled language. We highlight the
difficulties of mixing and matching two garbage collected languages
that know nothing about each other, and how to solve them by bringing
together existing techniques in the literature for safe memory
management (TODO ref). Finally, we show how to allow optionally
ascribing precise types to R functions, as a form of compiler-checked
documentation and to offer better safety guarantees.

\paragraph{Outline} The paper is organized as follows. We will first
walk through typical uses of H, before presenting its overall
architecture (Section \ref{sec:architecture}). We delve into a number
of special topics in later sections, covering how to represent foreign
values efficiently in a way that still allows for pattern matching
(Section \ref{sec:hexp}), optional static typing of dynamically typed
foreign values (Section \ref{sec:types}), creating R values from
Haskell (Section \ref{sec:vectors}) and efficient memory management in
the presence of two separately managed heaps with objects pointing to
arbitrary other objects in either heaps (Section \ref{sec:regions}).
We conclude with a discussion of the overheads of cross language
communication (Section \ref{sec:benchmarks}) and an overview of
related work (Section \ref{sec:related-work}).

\section{Overall architecture}
\label{sec:architecture}

- Embedded R.

\section{Special topics}

\subsection{A native view of foreign values}
\label{sec:hexp}

By default, and in order to avoid having to pay marshalling and
unmarshalling costs for each argument every time one invokes an
internal R function, we represent R values in exactly the same way
R does, as a pointer to a |SEXPREC| structure (defined in
@R/Rinternals.h@). This choice has a downside, however: Haskell's
pattern matching facilities are not immediately available, since only
algebraic datatypes can be pattern matched.

|HExp| is R's |SEXP| (or @*SEXPREC@) structure represented as
a (generalized) algebraic datatype. A simplified definition of |HExp|
would go along the lines of:
\begin{code}
  data HExp
  = Nil                                           -- NILSXP
  | Symbol { ... }                                -- SYMSXP
  | Real { ... }                                  -- REALSXP
  | ...
\end{code}
We define one constructor for each value of the |SEXPTYPE| enumeration
in @<RInternals.h>@.

For the sake of efficiency, we do *not* use |HExp| as the basic
datatype that all H generated code expects. That is, we do not use
|HExp| as the universe of R expressions, merely as a *view*. We
introduce the following *view function* to *locally* convert to
a |HExp|, given a |SEXP| from R.
\begin{code}
hexp :: SEXP s -> HExp
\end{code}
The fact that this conversion is local is crucial for good performance
of the translated code. It means that conversion happens at each use
site, and happens against values with a statically known form. Thus we
expect that the view function can usually be inlined, and the
short-lived |HExp| values that it creates compiled away by code
simplification rules applied by GHC. In this manner, we get the
convenience of pattern matching that comes with a *bona fide*
algebraic datatype, but without paying the penalty of allocating
long-lived data structures that need to be converted to and from
R internals every time we invoke internal R functions or C extension
functions.

Using an algebraic datatype for viewing R internal functions further
has the advantage that invariants about these structures can readily
be checked and enforced, including invariants that R itself does not
check for (e.g. that types that are special forms of the list type
really do have the right number of elements). The algebraic type
statically guarantees that no ill-formed type will ever be constructed
on the Haskell side and passed to R.

We also define an inverse of the view function:
\begin{code}
unhexp :: HExp -> SEXP
\end{code}

\subsection{Types for R}
\label{sec:types}

\subsection{R values are (usually) vectors}
\label{sec:vectors}

\subsection{Memory management}
\label{sec:regions}

One tricky aspect of bridging two languages with automatic memory
management such as R and Haskell is that we must be careful that the
garbage collectors (GC) of both languages see eye-to-eye. The embedded
R instance manages objects in its own heap, separate from the heap
that the GHC runtime manages. However, objects from one heap can
reference objects in the other heap and the other way around. This can
make garbage collection unsafe because neither GC's have a global view
of the object graph, only a partial view corresponding to the objects
in the heaps of each GC.

\subsubsection{Memory protection}

Fortunately, R provides a mechanism to "protect" objects from garbage
collection until they are unprotected. We can use this mechanism to
prevent R's GC from deallocating objects that are still referenced by
at least one object in the Haskell heap.

One particular difficulty with protection is that one must not forget
to unprotect objects that have been protected, in order to avoid
memory leaks. H uses "regions" for pinning an object in memory and
guaranteeing unprotection when the control flow exits a region.

\subsubsection{Memory regions}

There is currently one global region for R values, but in the future
H will have support for multiple (nested) regions. A region is opened
with the |runRegion| action, which creates a new region and executes
the given action in the scope of that region. All allocation of
R values during the course of the execution of the given action will
happen within this new region. All such values will remain protected
(i.e. pinned in memory) within the region. Once the action returns,
all allocated R values are marked as deallocatable garbage all at
once.

\begin{code}
runRegion :: (forall s . R s a) -> IO a
\end{code}

\subsubsection{Automatic memory management}

Nested regions work well as a memory management discipline for simple
scenarios when the lifetime of an object can easily be made to fit
within nested scopes. For more complex scenarios, it is often much
easier to let memory be managed completely automatically, though at
the cost of some memory overhead and performance penalty. H provides
a mechanism to attach finalizers to R values. This mechanism
piggybacks Haskell's GC to notify R's GC when it is safe to deallocate
a value.
\begin{code}
automatic :: MonadR m => R.SEXP s a -> m (R.SEXP G a)
\end{code}
In this way, values may be deallocated far earlier than reaching the
end of a region: As soon as Haskell's GC recognizes a value to no
longer be reachable, and if the R GC agrees, the value is prone to be
deallocated. Because automatic values have a lifetime independent of
the scope of the current region, they are tagged with the global
region |G| (a type synonym for |GlobalRegion|).

For example:
\begin{code}
do  x <- "1:1000"
    y <- "2"
    return $ automatic "x_hs * y_hs"
\end{code}
Automatic values can be mixed freely with other values.

\section{Benchmarks}
\label{sec:benchmarks}

\section{Related Work}
\label{sec:related-work}

\section{Conclusion}
\label{sec:conclusion}

%\acks

\bibliographystyle{abbrvnat}
\bibliography{references}

\end{document}
