#!/bin/sh

###############################################################################
 #
 #  This file is part of verkko-regression, a package that tests the Verkko
 #  whole-genome assembler.
 #
 #  Except as indicated otherwise, this is a 'United States Government Work',
 #  and is released in the public domain.
 #
 #  File 'README.licenses' in the root directory of this distribution
 #  contains full conditions and disclaimers.
 ##

#  To make this script a little bit less specific to each assembly,
#  it needs the name of the assembly as the only argument.

recp=$1
hifi=""
nano=""
mbg=""
ali=""


if [ -e /data/walenzbp/verkko-regression/binaries/MBG ] ; then
  mbg="--mbg /data/walenzbp/verkko-regression/binaries/MBG"
fi

if [ -e /data/walenzbp/verkko-regression/binaries/GraphAligner ] ; then
  ali="--graphaligner /data/walenzbp/verkko-regression/binaries/GraphAligner"
fi


if [ -e ../recipes/$recp/reads-hifi ] ; then
  hifi="--hifi ../recipes/$recp/reads-hifi/*"
fi

if [ -e ../recipes/$recp/reads-ont ] ; then
  nano="--nano ../recipes/$recp/reads-ont/*"
fi


./verkko/bin/verkko --keep-intermediate -d $recp $mbg $ali $hifi $nano
