Mocked: A mocking framework for the D Programming Language
==========================================================

Mocked is a record and playback mocking framework for the D Programming Language.

This is an initial version.  It supports mocking of classes, structs, and functions.  Expectations currently enforce call order and match expected parameters.  Mocked methods can be forced to return specific values.  The library does not yet support setting of output parameters.  There is no support for common features like ignoring parameter values, ignoring unexpected calls, matching parameters according to predicates instead of exact values, etc.

Currently this has only been tested on Linux.  It is unlikely to work on other platforms.
