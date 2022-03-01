A regression test suite and historical results for the [Verkko](https://github.com/marbl/verkko) assembler.

## Background

This is a set of scripts and configurations to compare results of Verkko across
different code points.  The driver script will update a local copy of the
verkko github repo, checkout a specific version of Verkko, and launch a
(user-supplied) set of assemblies.

Each assembly will compare itself against a reference genome (using quast)
and then compare quast results against a previously chosen curated assembly
and report differences in the quast results.

## Usage

The main driver is regression.pl.  This will update the local repo, checkout
a specific version of Verkko, build, and then launch assemblies on the grid.

The "chosen curated assembly" can be updated using update-refasm.sh.  

## Milestones

Nothing more than a list of special dates.  There aren't any yet.

Date            | Hash                                     | Milestone
--------------- | ---------------------------------------- | ------------------------------------------------------
--------------- | ---------------------------------------- | ------------------------------------------------------
