# RVVI Stubs

This directory contains "stub" implementations of various DPI calls implemented by ImperaDV.
It is a goal of the CV32E20 project to support a verification environment that can run with or without ImperasDV,
and these stubs are implemented to make it easier to use (or not) ImperasDV at compile-time.

The stubs are automatically compiled by the Makefiles as needed.
To build them seperately:
```
% make rvvi_stub CV_CORE=cv32e40p
```
